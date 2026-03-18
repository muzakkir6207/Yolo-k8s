# YOLO Inference on Kubernetes with GPU Support

**Production-ready YOLO inference server for Kubernetes with GPU acceleration and load testing**

Based on [Ultralytics YOLOv8](https://github.com/ultralytics/ultralytics) + Flask API

---

## Features

-  **GPU-accelerated inference** (NVIDIA GPU support)
-  **REST API** for image inference
-  **Kubernetes-native** deployment
-  **Load generator** included for GPU saturation testing
-  **Scalable** - from single node to multi-replica
-  **Production-ready** - health checks, resource limits, monitoring

---

## What's Included

```
yolo-k8s-ready/
├── Dockerfile              # YOLO + Flask image
├── server.py               # Flask API server
├── k8s/
│   └── deployment.yaml     # Kubernetes manifests (Deployment + Service)
├── load-generator/
│   ├── Dockerfile          # Load generator image
│   ├── load-client.py      # Load generation script
│   ├── deployment.yaml     # Load generator K8s manifest
│   └── README.md           # Load generator usage guide
├── README.md               # This file
└── SCALING_GUIDE.md        # GPU saturation strategies
```

---

## Quick Start

### Prerequisites

- Kubernetes cluster (K3s, K8s, K3d, etc.)
- kubectl configured
- Docker (for building images)
- NVIDIA GPU + device plugin (for GPU acceleration)

### 1. Build and Push Images

```bash
# Build YOLO inference image
docker build -t hamidhrf/yolo-flask:v1 .
docker push hamidhrf/yolo-flask:v1

# Build load generator image (optional)
cd load-generator
docker build -t hamidhrf/yolo-load-generator:v1 .
docker push hamidhrf/yolo-load-generator:v1
cd ..
```

Or use the build script:
```bash
./build.sh
```

### 2. Deploy YOLO Inference

```bash
kubectl apply -f k8s/deployment.yaml
```

### 3. Verify Deployment

```bash
# Check pod status
kubectl get pods -l app=yolo

# Check logs
kubectl logs -f deployment/yolo-inference

# Expected output:
# Loading model: yolov8n.pt
# Model loaded successfully
# Starting Flask server on 0.0.0.0:8080
```

### 4. Test the API

```bash
# Port forward
kubectl port-forward svc/yolo-api 8080:8080

# Health check
curl http://localhost:8080/health

# Inference (replace with your image)
curl -X POST -F "image=@your_image.jpg" http://localhost:8080/predict
```

**Response format:**
```json
{
  "detections": [
    {
      "class": "person",
      "confidence": 0.89,
      "bbox": [120.5, 45.3, 280.1, 450.7]
    }
  ],
  "count": 1
}
```

---

## GPU Configuration

### Enable GPU Support

The deployment is pre-configured for GPU. Ensure:

1. **NVIDIA device plugin is running:**
```bash
kubectl get pods -n kube-system | grep nvidia-device-plugin
```

2. **Check GPU allocation:**
```bash
kubectl describe pod -l app=yolo | grep -A 5 "Limits:"

# Should show:
#   Limits:
#     nvidia.com/gpu: 1
```

3. **Verify GPU usage:**
```bash
# On the node
nvidia-smi

# Or inside the pod
kubectl exec -it deployment/yolo-inference -- nvidia-smi
```

### GPU Workload Switching

If you have **multiple GPU workloads** on a **single GPU**, use this helper:

```bash
# Scale down other GPU workloads
kubectl scale deployment <other-gpu-workload> --replicas=0

# Scale up YOLO
kubectl scale deployment yolo-inference --replicas=1

# Switch back later
kubectl scale deployment yolo-inference --replicas=0
kubectl scale deployment <other-gpu-workload> --replicas=1
```

---

## Load Generation & GPU Saturation

See [SCALING_GUIDE.md](SCALING_GUIDE.md) for detailed GPU saturation strategies.

### Quick Load Test

```bash
# Deploy load generator (1 replica = ~15 req/s)
kubectl apply -f load-generator/deployment.yaml

# Watch load
kubectl logs -f deployment/yolo-load-generator

# Scale to saturate GPU
kubectl scale deployment yolo-load-generator --replicas=5   # ~75 req/s, 60-80% GPU
kubectl scale deployment yolo-load-generator --replicas=10  # ~150 req/s, 90-100% GPU

# Monitor GPU
nvidia-smi dmon -s u -c 100
```

**Expected throughput (H100 NVL GPU):**
- YOLOv8n: ~150-200 req/s @ 100% GPU
- YOLOv8s: ~100-150 req/s @ 100% GPU
- YOLOv8m: ~50-80 req/s @ 100% GPU

---

## Configuration

### Change YOLO Model

Edit `k8s/deployment.yaml`:
```yaml
env:
- name: YOLO_MODEL
  value: "yolov8s.pt"  # Options: yolov8n, yolov8s, yolov8m, yolov8l, yolov8x
```

### Adjust Resources

```yaml
resources:
  limits:
    nvidia.com/gpu: 1      # GPU allocation
    memory: "8Gi"          # Optional memory limit
    cpu: "4000m"           # Optional CPU limit
```

For systems with **large RAM (2TB+)**, you can remove memory/CPU limits entirely (current default).

### Custom Model Weights

1. Add your custom `.pt` file to the repo
2. Update Dockerfile:
```dockerfile
COPY your_custom_model.pt /app/
```
3. Update deployment env var:
```yaml
env:
- name: YOLO_MODEL
  value: "your_custom_model.pt"
```
4. Rebuild and push image

---

## Architecture

```
┌─────────────────────────────────────┐
│  Load Generator Pods (CPU-only)    │
│  ┌──────┐  ┌──────┐  ┌──────┐      │
│  │ Load │  │ Load │  │ Load │      │
│  │  #1  │  │  #2  │  │  #3  │      │
│  └──┬───┘  └──┬───┘  └──┬───┘      │ 
│     └─────────┴─────────┘          │
│              │ HTTP POST           │
└──────────────┼─────────────────────┘
               ▼
      ┌────────────────┐
      │  YOLO API      │
      │  (Flask)       │
      │  Port: 8080    │
      └────────┬───────┘
               │
               ▼
         ┌──────────┐
         │ GPU      │
         │ (NVIDIA) │
         └──────────┘
```

---

## Contributing

This is a research/experimentation setup. Feel free to fork and customize for your needs!

---

## License

MIT License (YOLO model follows Ultralytics AGPL-3.0)

---

## References

- [Ultralytics YOLO](https://github.com/ultralytics/ultralytics)
- [YOLO Documentation](https://docs.ultralytics.com/)
- [Kubernetes GPU Support](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)

---

## Author

Created for YOLO inference experiments on Kubernetes with GPU acceleration in FH dortmund by Hamidreza Fathollahzadeh

**Docker Hub:**
- YOLO Inference: `hamidhrf/yolo-flask:v1`
- Load Generator: `hamidhrf/yolo-load-generator:v1`