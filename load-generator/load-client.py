#!/usr/bin/env python3
"""
YOLO inference load generator.

Default behavior is continuous load, but callers can pass --duration to stop after
an explicit user-chosen runtime.
"""
import argparse
import io
import logging
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import requests

try:
    import numpy as np
except ImportError:
    np = None

try:
    from PIL import Image
except ImportError:
    Image = None

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class LoadGenerator:
    def __init__(
        self,
        api_url,
        num_workers=4,
        image_size=640,
        summary_interval=10,
        worker_delay_ms=0,
    ):
        self.api_url = api_url
        self.num_workers = num_workers
        self.image_size = image_size
        self.summary_interval = summary_interval
        self.worker_delay_ms = worker_delay_ms
        self.total_requests = 0
        self.total_errors = 0
        self.running = True
        self.lock = threading.Lock()

    def generate_random_image(self):
        """Generate a random RGB image payload."""
        if np is not None and Image is not None:
            img_array = np.random.randint(0, 255, (self.image_size, self.image_size, 3), dtype=np.uint8)
            img = Image.fromarray(img_array)

            img_bytes = io.BytesIO()
            img.save(img_bytes, format='JPEG')
            img_bytes.seek(0)
            return img_bytes, "image/jpeg", "test.jpg"

        # Fallback for local terminals that have requests but not numpy/Pillow.
        # PPM is trivial to generate with the stdlib and Pillow on the server can open it.
        header = f"P6\n{self.image_size} {self.image_size}\n255\n".encode("ascii")
        payload = header + os.urandom(self.image_size * self.image_size * 3)
        img_bytes = io.BytesIO(payload)
        img_bytes.seek(0)
        return img_bytes, "image/x-portable-pixmap", "test.ppm"

    def send_request(self, worker_id):
        """Send a single inference request."""
        try:
            img_bytes, content_type, filename = self.generate_random_image()
            files = {'image': (filename, img_bytes, content_type)}

            start_time = time.time()
            response = requests.post(f"{self.api_url}/predict", files=files, timeout=30)
            latency = time.time() - start_time

            with self.lock:
                if response.status_code == 200:
                    self.total_requests += 1
                    current_requests = self.total_requests
                else:
                    self.total_errors += 1
                    current_requests = self.total_requests

            if response.status_code == 200:
                if current_requests % 100 == 0:
                    logger.info(
                        "Worker %s: %s requests | Last latency: %.1fms",
                        worker_id,
                        current_requests,
                        latency * 1000,
                    )
                return True

            logger.error("Worker %s: HTTP %s", worker_id, response.status_code)
            return False

        except Exception as exc:
            with self.lock:
                self.total_errors += 1
            logger.error("Worker %s: %s", worker_id, exc)
            return False

    def worker_loop(self, worker_id):
        """Continuous inference loop for one worker."""
        logger.info("Worker %s started", worker_id)
        while self.running:
            self.send_request(worker_id)
            if self.worker_delay_ms > 0 and self.running:
                time.sleep(self.worker_delay_ms / 1000.0)

    def snapshot(self):
        with self.lock:
            return self.total_requests, self.total_errors

    def run(self, duration=None):
        """Run load generation until duration expires or interrupted."""
        logger.info("Starting load generation with %s workers", self.num_workers)
        logger.info("Target: %s", self.api_url)
        logger.info("Image size: %sx%s", self.image_size, self.image_size)
        logger.info("Worker delay: %sms", self.worker_delay_ms)
        logger.info("Duration: %s", f"{duration}s" if duration else "infinite")

        start_time = time.time()
        next_summary = start_time + self.summary_interval
        deadline = (start_time + duration) if duration else None

        with ThreadPoolExecutor(max_workers=self.num_workers) as executor:
            futures = [executor.submit(self.worker_loop, i) for i in range(self.num_workers)]

            try:
                while True:
                    now = time.time()
                    if deadline and now >= deadline:
                        logger.info("Requested duration reached, stopping load generation")
                        self.running = False
                        break

                    if now >= next_summary:
                        total_requests, total_errors = self.snapshot()
                        elapsed = now - start_time
                        qps = total_requests / elapsed if elapsed > 0 else 0
                        logger.info(
                            "Summary: %s requests, %s errors, %.1f req/s",
                            total_requests,
                            total_errors,
                            qps,
                        )
                        next_summary = now + self.summary_interval

                    time.sleep(1)
            except KeyboardInterrupt:
                logger.info("Stopping load generation...")
                self.running = False

            for future in futures:
                future.result()

        total_requests, total_errors = self.snapshot()
        total_time = time.time() - start_time
        final_qps = total_requests / total_time if total_time > 0 else 0

        logger.info("=" * 60)
        logger.info("Load generation complete")
        logger.info("Total requests: %s", total_requests)
        logger.info("Total errors: %s", total_errors)
        logger.info("Duration: %.1fs", total_time)
        logger.info("Average QPS: %.1f", final_qps)
        logger.info("=" * 60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='YOLO Inference Load Generator')
    parser.add_argument('--api-url', default='http://yolo-api:8080',
                        help='YOLO API URL (default: http://yolo-api:8080)')
    parser.add_argument('--workers', type=int, default=4,
                        help='Number of concurrent workers (default: 4)')
    parser.add_argument('--duration', type=int, default=None,
                        help='Duration in seconds (default: run forever)')
    parser.add_argument('--image-size', type=int, default=640,
                        help='Image size (default: 640)')
    parser.add_argument('--summary-interval', type=int, default=10,
                        help='Summary logging interval in seconds (default: 10)')
    parser.add_argument('--worker-delay-ms', type=int, default=0,
                        help='Delay after each request per worker in milliseconds (default: 0)')

    args = parser.parse_args()

    if args.worker_delay_ms < 0:
        parser.error('--worker-delay-ms must be >= 0')

    generator = LoadGenerator(
        api_url=args.api_url,
        num_workers=args.workers,
        image_size=args.image_size,
        summary_interval=args.summary_interval,
        worker_delay_ms=args.worker_delay_ms,
    )

    generator.run(duration=args.duration)
