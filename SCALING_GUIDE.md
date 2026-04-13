# GPU Saturation Guide

For step-by-step load generation with a single inference pod and one-by-one replica increases, see [LOAD_GENERATION_GUIDE.md](LOAD_GENERATION_GUIDE.md).

The basic YOLO deployment is a **passive API server**. It waits for requests but generates NO load by itself.

```yaml
# This just sits idle waiting for requests:
replicas: 1  # ← Just 1 pod with GPU, doing nothing until you send requests
```

## Solution: Deploy Separate Load Generator

### Architecture

```
┌─────────────────────────────────────────┐
│  Load Generator Pods (CPU only)         │
│  - Send continuous requests             │
│  - Scale from 1 → 10+ replicas          │
│                                         │
│  ┌──────┐  ┌──────┐  ┌──────┐           │
│  │ Load │  │ Load │  │ Load │  ...      │
│  │  #1  │  │  #2  │  │  #3  │           │
│  └──┬───┘  └──┬───┘  └──┬───┘           │
│     │         │         │               │
│     └─────────┴─────────┘               │
│               │                         │
└───────────────┼─────────────────────────┘
                │ HTTP requests
                ▼
        ┌──────────────┐
        │  YOLO API    │
        │  (1 replica) │
        │  with GPU    │
        └──────────────┘
                │
                ▼
          ┌──────────┐
          │  H100 GPU│
          └──────────┘
```

## Step-by-Step Saturation

### 1. Deploy YOLO Inference (GPU)

```bash
# Ensure GPU is enabled in k8s/deployment.yaml
kubectl apply -f k8s/deployment.yaml

# Verify GPU is allocated
kubectl describe pod -l app=yolo | grep -A 5 "Limits:"
```

### 2. Deploy Load Generator (CPU)

```bash
kubectl apply -f load-generator/deployment.yaml

# Check it's running
kubectl get pods -l app=yolo-load
kubectl logs -f deployment/yolo-load-generator
```

Expected output:
```
Worker 0 started
Worker 1 started
Worker 2 started
Worker 3 started
Summary: 400 requests, 0 errors, 45.2 req/s
```

### 3. Monitor GPU Utilization

```bash
# On the host/node where pod is running
nvidia-smi dmon -s u -c 100

# Or in the pod
kubectl exec -it deployment/yolo-inference -- nvidia-smi
```

### 4. Scale Load Generator Until GPU Saturates

```bash
# Start: 1 replica × 4 workers = 4 concurrent requests
kubectl get deployment yolo-load-generator
# NAME                   READY   UP-TO-DATE   AVAILABLE
# yolo-load-generator    1/1     1            1

# Check GPU - probably 5-15% utilization
nvidia-smi

# Scale to 3 replicas
kubectl scale deployment yolo-load-generator --replicas=3
# Now: 3 × 4 = 12 concurrent requests
# Expected GPU: 25-40%

# Scale to 5 replicas  
kubectl scale deployment yolo-load-generator --replicas=5
# Now: 5 × 4 = 20 concurrent requests
# Expected GPU: 50-70%

# Scale to 8 replicas
kubectl scale deployment yolo-load-generator --replicas=8
# Now: 8 × 4 = 32 concurrent requests
# Expected GPU: 80-90%

# Scale to 10 replicas
kubectl scale deployment yolo-load-generator --replicas=10
# Now: 10 × 4 = 40 concurrent requests
# Expected GPU: 95-100% ✓ SATURATED
```

### 5. Fine-Tune Workers Per Pod (Optional)

If scaling replicas alone doesn't saturate, increase workers per pod:

```bash
# Edit deployment
kubectl edit deployment yolo-load-generator

# Change:
env:
- name: WORKERS
  value: "8"  # ← Was 4, now 8

# Now: 10 replicas × 8 workers = 80 concurrent requests
```

## Monitoring Saturation

### GPU Utilization
```bash
# Live monitoring
watch -n 1 nvidia-smi

# Look for:
# +-----------------------------------------------------------------------------+
# | Processes:                                                                  |
# |  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
# |        ID   ID                                                   Usage      |
# |=============================================================================|
# |    0   N/A  N/A   1234567      C   python                           4567MiB|
# +-----------------------------------------------------------------------------+
#                                      ↑                                   ↑
#                              Compute process                      High memory = good
```

### Request Throughput
```bash
# Check load generator logs
kubectl logs -f deployment/yolo-load-generator | grep "req/s"

# Output:
# Summary: 1200 requests, 0 errors, 127.5 req/s
# Summary: 2400 requests, 0 errors, 134.2 req/s
```

### API Latency
```bash
# Port forward metrics
kubectl port-forward svc/yolo-api 8080:8080

# Check Prometheus metrics
curl http://localhost:8080/metrics | grep yolo_inference_latency

# Look for:
# yolo_inference_latency_seconds_bucket{le="0.05"} 1234
# yolo_inference_latency_seconds_sum 45.67
# yolo_inference_latency_seconds_count 2400
```

## Typical Results (H100 NVL)

| YOLO Model | Load Generator | Throughput | GPU % | Latency |
|------------|----------------|------------|-------|---------|
| yolov8n    | 5 × 4 workers  | ~400/s     | 50%   | 12ms    |
| yolov8n    | 10 × 8 workers | ~800/s     | 95%   | 25ms    |
| yolov8s    | 10 × 8 workers | ~500/s     | 95%   | 40ms    |
| yolov8m    | 10 × 8 workers | ~250/s     | 95%   | 80ms    |


## Advanced: Horizontal Pod Autoscaler (HPA)

Auto-scale load generator based on GPU utilization:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: yolo-load-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: yolo-load-generator
  minReplicas: 1
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

This auto-scales load generator pods to maintain steady pressure.
