# YOLO Load Generator

Generates continuous inference load to saturate GPU.

## Strategy to Saturate GPU

### Step 1: Deploy YOLO Inference (1 replica with GPU)
```bash
# Make sure GPU is enabled in k8s/deployment.yaml
kubectl apply -f k8s/
```

### Step 2: Deploy Load Generator (Start with 1 replica)
```bash
# Build and push image (optional, or use Python directly)
docker build -t hamidhrf/yolo-load-generator:v1 load-generator/
docker push hamidhrf/yolo-load-generator:v1

# Deploy
kubectl apply -f load-generator/deployment.yaml
```

### Step 3: Scale Load Generator to Saturate GPU
```bash
# Start with 1 replica
kubectl get pods -l app=yolo-load

# Watch GPU utilization
watch -n 1 nvidia-smi

# Scale up gradually
kubectl scale deployment yolo-load-generator --replicas=2
kubectl scale deployment yolo-load-generator --replicas=4
kubectl scale deployment yolo-load-generator --replicas=8

# Keep scaling until GPU hits 95-100% utilization
```

### Step 4: Monitor
```bash
# Check logs
kubectl logs -f deployment/yolo-load-generator

# Check GPU
nvidia-smi dmon -s u -c 100
```

## Tuning Parameters

### Workers per Pod
Edit `load-generator/deployment.yaml`:
```yaml
env:
- name: WORKERS
  value: "8"  # Increase for more concurrent requests per pod
```

### Replicas (Pods)
```bash
# Scale deployment
kubectl scale deployment yolo-load-generator --replicas=10
```

### Total Load = (Replicas × Workers per Pod)
Examples:
- 1 replica × 4 workers = 4 concurrent requests
- 5 replicas × 4 workers = 20 concurrent requests
- 10 replicas × 8 workers = 80 concurrent requests

## Alternative: Run Load Generator Locally (No K8s)

```bash
# Port forward YOLO API
kubectl port-forward svc/yolo-api 8080:8080

# Run load generator locally
python load-generator/load-client.py \
  --api-url http://localhost:8080 \
  --workers 16 \
  --duration 300  # 5 minutes
```

## Expected Results

With H100 NVL GPU:
- YOLOv8n: ~500-1000 inferences/sec (saturated)
- YOLOv8s: ~300-500 inferences/sec
- YOLOv8m: ~150-300 inferences/sec

Monitor with:
```bash
# GPU utilization
nvidia-smi dmon -s u

# API metrics
kubectl port-forward svc/yolo-api 8080:8080
curl http://localhost:8080/metrics
```
