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
├── LOAD_GENERATION_GUIDE.md # Step-by-step load generation workflow
├── LOAD_TEST_CASES.md      # Detailed test-case series for experiments
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

### 2. Deploy YOLO Inference

```bash
kubectl apply -f k8s/deployment.yaml
```

### 3. Verify Deployment

```bash
# Check pod status
kubectl get pods -n yolo1 -l app=yolo

# Check logs
kubectl logs -f deployment/yolo-inference -n yolo1

# Expected output:
# Loading model: yolov8x.pt
# Model loaded successfully
# Starting Flask server on 0.0.0.0:8080
```

### 4. Test the API

```bash
# Port forward
kubectl port-forward svc/yolo-api -n yolo1 8080:8080

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
kubectl describe pod -n yolo1 -l app=yolo | grep -A 5 "Limits:"

# Should show:
#   Limits:
#     nvidia.com/gpu: 1
```

3. **Verify GPU usage:**
```bash
# On the node
nvidia-smi

# Or inside the pod
kubectl exec -it deployment/yolo-inference -n yolo1 -- nvidia-smi
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

See [LOAD_GENERATION_GUIDE.md](LOAD_GENERATION_GUIDE.md) for the current load-generation workflow.

See [LOAD_TEST_CASES.md](LOAD_TEST_CASES.md) for the full experiment matrix, including:

- 1-instance uniform load sweeps
- 2-instance and 3-instance uniform load sweeps
- varied per-instance load cases
- baseline, cleanup, and troubleshooting steps

See [SCALING_GUIDE.md](SCALING_GUIDE.md) for broader GPU saturation strategies.

### Quick Load Test

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=1
kubectl rollout status deployment/yolo-inference -n yolo1
kubectl get pods -n yolo1 -l app=yolo

# Port-forward one selected pod on a fresh local port
POD1="yolo-inference-xxxx"
kubectl port-forward --address 127.0.0.1 -n yolo1 pod/$POD1 19081:8080

# Run load locally from another terminal
cd load-generator
./run_load_local.sh 600 --percent-load 10 --api-url http://127.0.0.1:19081 --max-workers-per-instance 10
```

### Calibrated Multi-Instance Reference

This command pattern worked better in practice for moderate multi-instance tests because it:

- uses one local target per Yolo pod
- lowers the worker reference from `10` to `5`
- adds a small per-worker delay to avoid jumping straight to an overly aggressive load level

Base settings:

- `--percent-load 20`
- `--max-workers-per-instance 5`
- `--worker-delay-ms 100`

Setup pattern:

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=<N>
kubectl rollout status deployment/yolo-inference -n yolo1
kubectl get pods -n yolo1 -l app=yolo
```

Start one port-forward per target pod on fresh local ports such as `19081`, `19082`, `19083`, `19084`, `19085`.

Exact execution commands:

For `2` instances:

```bash
cd load-generator
./run_load_local.sh 600 \
  --percent-load 20 \
  --api-url http://127.0.0.1:19081 \
  --api-url http://127.0.0.1:19082 \
  --max-workers-per-instance 5 \
  --worker-delay-ms 100
```

For `3` instances:

```bash
cd load-generator
./run_load_local.sh 600 \
  --percent-load 20 \
  --api-url http://127.0.0.1:19081 \
  --api-url http://127.0.0.1:19082 \
  --api-url http://127.0.0.1:19083 \
  --max-workers-per-instance 5 \
  --worker-delay-ms 100
```

For `4` instances:

```bash
cd load-generator
./run_load_local.sh 600 \
  --percent-load 20 \
  --api-url http://127.0.0.1:19081 \
  --api-url http://127.0.0.1:19082 \
  --api-url http://127.0.0.1:19083 \
  --api-url http://127.0.0.1:19084 \
  --max-workers-per-instance 5 \
  --worker-delay-ms 100
```

For `5` instances:

```bash
cd load-generator
./run_load_local.sh 600 \
  --percent-load 20 \
  --api-url http://127.0.0.1:19081 \
  --api-url http://127.0.0.1:19082 \
  --api-url http://127.0.0.1:19083 \
  --api-url http://127.0.0.1:19084 \
  --api-url http://127.0.0.1:19085 \
  --max-workers-per-instance 5 \
  --worker-delay-ms 100
```

Observed GPU behavior from the validated `2`-instance run:

- `sm` was mostly in the `17%` to `36%` range
- `mem` was mostly in the `4%` to `7%` range

This is a better starting point when the default worker-only scaling is too coarse and different percentage settings collapse into the same effective GPU load.

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

Created for YOLO inference experiments on Kubernetes with GPU acceleration at FH dortmund by Hamidreza Fathollahzadeh

**Docker Hub:**
- YOLO Inference: `hamidhrf/yolo-flask:v1`
- Load Generator: `hamidhrf/yolo-load-generator:v1`
