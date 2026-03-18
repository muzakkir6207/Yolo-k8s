#!/usr/bin/env python3
"""
YOLO Inference API Server
"""
from ultralytics import YOLO
from flask import Flask, request, jsonify
import io
from PIL import Image
import os

app = Flask(__name__)

MODEL_NAME = os.getenv('YOLO_MODEL', 'yolov8n.pt')
print(f"Loading model: {MODEL_NAME}", flush=True)
model = YOLO(MODEL_NAME)
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
    
    results = model.predict(img, verbose=False)
    
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
    app.run(host='0.0.0.0', port=8080, debug=False)
