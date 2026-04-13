#!/usr/bin/env python3
"""
YOLO Inference API Server
"""
import io
import os

import torch
from flask import Flask, jsonify, request
from PIL import Image
from ultralytics import YOLO

app = Flask(__name__)

MODEL_NAME = os.getenv("YOLO_MODEL", "yolov8x.pt")
DEVICE = "cuda:0" if torch.cuda.is_available() else "cpu"
PREDICT_IMGSZ = int(os.getenv("YOLO_IMAGE_SIZE", "1280"))
PREDICT_HALF = os.getenv("YOLO_HALF", "false").lower() in {"1", "true", "yes"} and DEVICE != "cpu"

print(f"Loading model: {MODEL_NAME}", flush=True)
model = YOLO(MODEL_NAME)
if DEVICE != "cpu":
    model.to(DEVICE)
print(f"Using device={DEVICE} imgsz={PREDICT_IMGSZ} half={PREDICT_HALF}", flush=True)
print("Model loaded successfully", flush=True)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy', 'model': MODEL_NAME}), 200

@app.route('/predict', methods=['POST'])
def predict():
    if 'image' not in request.files:
        return jsonify({'error': 'No image provided'}), 400
    
    img_file = request.files['image']
    img = Image.open(io.BytesIO(img_file.read()))
    
    results = model.predict(
        img,
        verbose=False,
        device=DEVICE,
        imgsz=PREDICT_IMGSZ,
        half=PREDICT_HALF,
    )
    
    detections = []
    for r in results:
        for box in r.boxes:
            detections.append({
                'class': r.names[int(box.cls)],
                'confidence': float(box.conf),
                'bbox': box.xyxy[0].tolist()
            })
    
    return jsonify({
        'detections': detections,
        'count': len(detections)
    })

if __name__ == '__main__':
    print("Starting Flask server on 0.0.0.0:8080", flush=True)
    app.run(host='0.0.0.0', port=8080, debug=False, threaded=True)
