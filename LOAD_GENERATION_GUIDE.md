# YOLO Load Generation Guide

This repo supports two modes for Yolo load generation:

- recommended: one-shot Job with a user-specified duration
- optional: continuous Deployment, scaled to `0` by default

The important distinction is:

- `yolo-inference` serves inference
- `yolo-load-generator` creates artificial load against `yolo-inference`

## Recommended Way To Run Load

Use the launcher script and pass the runtime at execution time.

```bash
cd ~/Yolo-k8s
./load-generator/run_load_job.sh <duration-seconds> [parallelism] [workers] [image-size]
```

Examples:

```bash
./load-generator/run_load_job.sh 600
./load-generator/run_load_job.sh 300 1
./load-generator/run_load_job.sh 900 2 8 1280
```

Arguments:

- `duration-seconds`: how long each load pod should run
- `parallelism`: how many load pods to run in parallel, default `1`
- `workers`: concurrent request workers per pod, default `8`
- `image-size`: generated image size, default `1280`

## What The Launcher Does

`load-generator/run_load_job.sh` creates a one-shot Kubernetes Job in namespace `yolo1`.
Each pod runs:

```bash
python /workspace/load-generator/load-client.py --api-url=... --workers=... --image-size=... --duration=<your-runtime>
```

The Job mounts the repo directory from the node:

- host path: `/home/user/Yolo-k8s/load-generator`
- container path: `/workspace/load-generator`

That means the latest repo version of `load-client.py` is used immediately without rebuilding the image.

The Job also has:

- `restartPolicy: Never`
- `backoffLimit: 0`
- `ttlSecondsAfterFinished: 120`

So it stops automatically and does not keep consuming GPU indefinitely.

## Watch A Run

```bash
kubectl get jobs -n yolo1
kubectl get pods -n yolo1 -l app=yolo-load -w
kubectl logs -n yolo1 -l app=yolo-load --all-containers=true -f
```

The launcher also prints the exact `job-name` selector.

## Verify GPU Impact

```bash
kubectl top pods -n yolo1
kubectl logs -n yolo1 -l app=yolo-load --all-containers=true -f
nvidia-smi dmon -s u -c 20
```

The load client prints periodic summaries while it is running, including total requests, errors, and average request rate.

## Continuous Deployment Mode

A continuous Deployment manifest still exists at:

- `load-generator/deployment.yaml`

But it is intentionally safe now:

- `replicas: 0`
- it does not consume resources until you explicitly scale it up
- it also mounts `/home/user/Yolo-k8s/load-generator` so it uses the repo version of `load-client.py`

Manual start:

```bash
kubectl apply -f load-generator/deployment.yaml
kubectl scale deployment yolo-load-generator -n yolo1 --replicas=1
```

Manual stop:

```bash
kubectl scale deployment yolo-load-generator -n yolo1 --replicas=0
```

## Operational Note

If you only want a controlled experiment for a fixed interval, use the Job launcher.
Do not use the continuous Deployment for that case.
