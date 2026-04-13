# Load Generation Guide

This guide shows how to increase load on the YOLO deployment one step at a time and measure the GPU effect after each change.

It assumes the current manifests in this repo:

- Namespace: `yolo1`
- Inference deployment: `yolo-inference`
- Load deployment: `yolo-load-generator`
- Default model: `yolov8x.pt`
- Default image size: `1280`
- Default load workers per load pod: `8`

## 1. Start With One Inference Pod

Keep inference at a single replica while you test the effect of load-generator pods.

```bash
kubectl apply -f k8s/deployment.yaml
kubectl scale deployment yolo-inference -n yolo1 --replicas=1
kubectl rollout status deployment/yolo-inference -n yolo1
kubectl get pods -n yolo1 -l app=yolo
```

## 2. Start With One Load Pod

Deploy the load generator, but keep it at exactly one replica first.

```bash
kubectl apply -f load-generator/deployment.yaml
kubectl scale deployment yolo-load-generator -n yolo1 --replicas=1
kubectl rollout status deployment/yolo-load-generator -n yolo1
kubectl get pods -n yolo1 -l app=yolo-load
```

## 3. Measure the Baseline

Use these commands after each scale step:

```bash
kubectl top pods -n yolo1
kubectl logs -f deployment/yolo-load-generator -n yolo1
nvidia-smi dmon -s u -c 20
```

Watch the `sm` column from `nvidia-smi dmon`. That is the easiest signal for GPU load.

Example:

```text
# gpu     sm    mem    enc    dec    jpg    ofa
    0     12      3      0      0      0      0
```

With one inference pod and one load-generator pod, a result around `10-15%` GPU SM utilization is reasonable for this setup.

## 4. Increase Load One Pod at a Time

Scale only the load-generator deployment and measure after each step.

```bash
kubectl scale deployment yolo-load-generator -n yolo1 --replicas=2
kubectl rollout status deployment/yolo-load-generator -n yolo1
nvidia-smi dmon -s u -c 20

kubectl scale deployment yolo-load-generator -n yolo1 --replicas=3
kubectl rollout status deployment/yolo-load-generator -n yolo1
nvidia-smi dmon -s u -c 20

kubectl scale deployment yolo-load-generator -n yolo1 --replicas=4
kubectl rollout status deployment/yolo-load-generator -n yolo1
nvidia-smi dmon -s u -c 20
```

Continue with `5`, `6`, and so on only after checking the previous step.

## 5. Record the Result After Each Step

Use a simple table like this:

| Load pods | GPU SM util | Inference CPU | Notes |
|-----------|-------------|---------------|-------|
| 1 | 12% | 1255m | Baseline |
| 2 | ? | ? | |
| 3 | ? | ? | |
| 4 | ? | ? | |

Get inference CPU from:

```bash
kubectl top pods -n yolo1
```

## 6. How to Interpret the Results

### Case A: GPU load increases

If GPU `sm` goes up as you add load pods, keep increasing one step at a time until you reach the target.

### Case B: GPU load plateaus

If GPU `sm` stays almost flat while the inference pod CPU keeps rising, the single inference pod is the bottleneck.

In that case, stop increasing load-generator replicas and increase inference replicas instead:

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=2
kubectl rollout status deployment/yolo-inference -n yolo1
```

Then repeat the same one-by-one load-generator ramp.

## 7. Reduce or Stop Load

To reduce load:

```bash
kubectl scale deployment yolo-load-generator -n yolo1 --replicas=1
```

To stop load generation:

```bash
kubectl scale deployment yolo-load-generator -n yolo1 --replicas=0
```

To stop inference too:

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=0
```

## 8. Quick Checklist

```bash
kubectl get pods -n yolo1
kubectl top pods -n yolo1
kubectl logs -f deployment/yolo-load-generator -n yolo1
nvidia-smi dmon -s u -c 20
```

If you want controlled experimentation, change only one thing at a time:

1. Keep inference replicas fixed.
2. Increase load-generator replicas by one.
3. Measure GPU load.
4. Repeat.
