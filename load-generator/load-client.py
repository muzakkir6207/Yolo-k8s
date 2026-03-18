#!/usr/bin/env python3
"""
YOLO Inference Load Generator
Saturates GPU by sending continuous inference requests
"""
import requests
import numpy as np
from PIL import Image
import io
import time
import threading
import logging
from concurrent.futures import ThreadPoolExecutor
import argparse

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class LoadGenerator:
    def __init__(self, api_url, num_workers=4, image_size=640):
        self.api_url = api_url
        self.num_workers = num_workers
        self.image_size = image_size
        self.total_requests = 0
        self.total_errors = 0
        self.running = True
        
    def generate_random_image(self):
        """Generate random image as bytes"""
        img_array = np.random.randint(0, 255, (self.image_size, self.image_size, 3), dtype=np.uint8)
        img = Image.fromarray(img_array)
        
        # Convert to bytes
        img_bytes = io.BytesIO()
        img.save(img_bytes, format='JPEG')
        img_bytes.seek(0)
        return img_bytes
    
    def send_request(self, worker_id):
        """Send single inference request"""
        try:
            img_bytes = self.generate_random_image()
            files = {'image': ('test.jpg', img_bytes, 'image/jpeg')}
            
            start_time = time.time()
            response = requests.post(f"{self.api_url}/predict", files=files, timeout=30)
            latency = time.time() - start_time
            
            if response.status_code == 200:
                self.total_requests += 1
                if self.total_requests % 100 == 0:
                    logger.info(f"Worker {worker_id}: {self.total_requests} requests | "
                              f"Last latency: {latency*1000:.1f}ms")
                return True
            else:
                self.total_errors += 1
                logger.error(f"Worker {worker_id}: HTTP {response.status_code}")
                return False
                
        except Exception as e:
            self.total_errors += 1
            logger.error(f"Worker {worker_id}: {e}")
            return False
    
    def worker_loop(self, worker_id):
        """Continuous inference loop for one worker"""
        logger.info(f"Worker {worker_id} started")
        while self.running:
            self.send_request(worker_id)
    
    def run(self, duration=None):
        """Run load generation"""
        logger.info(f"Starting load generation with {self.num_workers} workers")
        logger.info(f"Target: {self.api_url}")
        logger.info(f"Image size: {self.image_size}x{self.image_size}")
        
        start_time = time.time()
        
        with ThreadPoolExecutor(max_workers=self.num_workers) as executor:
            futures = [executor.submit(self.worker_loop, i) for i in range(self.num_workers)]
            
            try:
                if duration:
                    time.sleep(duration)
                    self.running = False
                else:
                    # Run indefinitely
                    while True:
                        time.sleep(10)
                        elapsed = time.time() - start_time
                        qps = self.total_requests / elapsed if elapsed > 0 else 0
                        logger.info(f"Summary: {self.total_requests} requests, "
                                  f"{self.total_errors} errors, "
                                  f"{qps:.1f} req/s")
            except KeyboardInterrupt:
                logger.info("Stopping load generation...")
                self.running = False
            
            # Wait for workers to finish
            for future in futures:
                future.result()
        
        total_time = time.time() - start_time
        final_qps = self.total_requests / total_time if total_time > 0 else 0
        
        logger.info("=" * 60)
        logger.info(f"Load generation complete")
        logger.info(f"Total requests: {self.total_requests}")
        logger.info(f"Total errors: {self.total_errors}")
        logger.info(f"Duration: {total_time:.1f}s")
        logger.info(f"Average QPS: {final_qps:.1f}")
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
    
    args = parser.parse_args()
    
    generator = LoadGenerator(
        api_url=args.api_url,
        num_workers=args.workers,
        image_size=args.image_size
    )
    
    generator.run(duration=args.duration)
