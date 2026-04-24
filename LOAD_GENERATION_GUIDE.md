# YOLO Load Generation Guide

This repo supports two ways to generate Yolo load:

- recommended: local terminal load, with no extra Kubernetes load pods
- optional: one-shot Kubernetes Job, if you explicitly want in-cluster load pods

If you want `kubectl get pods -n yolo1 -l app=yolo` to show only `yolo-inference` pods, use the local-terminal workflow below.

## Recommended: Local Terminal Load

This mode sends requests from your shell session. It does not create any `yolo-load-*` pods.

### Important routing note

For a single replica, port-forwarding the service is fine.

For multiple replicas, a single local entrypoint such as:

```bash
kubectl port-forward -n yolo1 svc/yolo-api 18080:8080
```

does not guarantee that your local requests are spread across all Yolo pods.

If you want replica-aware load, or different load per instance, port-forward each Yolo pod separately and target each pod explicitly.

### Terminal 1: expose one or more Yolo pods locally

For one instance:

```bash
kubectl port-forward -n yolo1 pod/<yolo-pod-1> 18081:8080
```

For three instances:

```bash
kubectl port-forward -n yolo1 pod/<yolo-pod-1> 18081:8080
kubectl port-forward -n yolo1 pod/<yolo-pod-2> 18082:8080
kubectl port-forward -n yolo1 pod/<yolo-pod-3> 18083:8080
```

Leave those terminals running for the duration of the test.

### Terminal 2: run the load

You can run either:

- an explicit worker count
- a single percentage applied to every targeted instance
- different percentages for different targeted instances

```bash
cd ~/Yolo-k8s
./load-generator/run_load_local.sh <duration-seconds> [workers] [image-size]
./load-generator/run_load_local.sh <duration-seconds> --percent-load <1-100> [--instance-count N] [--max-workers-per-instance N] [--image-size PX] [--api-url URL]
./load-generator/run_load_local.sh <duration-seconds> --percent-load <1-100> --api-url URL [--api-url URL ...] [--max-workers-per-instance N] [--image-size PX]
./load-generator/run_load_local.sh <duration-seconds> --percent-loads <P1,P2,...> --api-url URL [--api-url URL ...] [--max-workers-per-instance N] [--image-size PX]
```

Examples:

```bash
./load-generator/run_load_local.sh 600 1 --api-url http://127.0.0.1:18081
./load-generator/run_load_local.sh 600 --percent-load 10 --api-url http://127.0.0.1:18081 --max-workers-per-instance 10
./load-generator/run_load_local.sh 600 --percent-load 10 --api-url http://127.0.0.1:18081 --api-url http://127.0.0.1:18082 --api-url http://127.0.0.1:18083 --max-workers-per-instance 10
./load-generator/run_load_local.sh 600 --percent-loads 10,20,30 --api-url http://127.0.0.1:18081 --api-url http://127.0.0.1:18082 --api-url http://127.0.0.1:18083 --max-workers-per-instance 10
```

### Meaning of percentage mode

Percentage mode is defined per targeted instance.

Example with:

- `--max-workers-per-instance 10`
- three pod-specific `--api-url` values
- `--percent-load 10`

The reference is:

- `10` workers per instance
- each targeted pod gets `10%` of its own reference

So `10%` maps to about `1` worker per targeted pod.

If you use:

- `--percent-loads 10,20,30`
- `--max-workers-per-instance 10`

then the script maps that to approximately:

- pod 1: `1` worker
- pod 2: `2` workers
- pod 3: `3` workers

The script prints the exact mapping before it starts.

### Typical experiment workflow

1. Scale `yolo-inference` to the number of instances you want to test.
2. Wait for the rollout to finish.
3. Port-forward each Yolo pod you want to target.
4. Run one timed load cycle from another terminal.
5. Watch GPU manually with `nvidia-smi` if needed.

Example for `1` instance at `10%` per instance:

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=1
kubectl rollout status deployment/yolo-inference -n yolo1

kubectl get pods -n yolo1 -l app=yolo
kubectl port-forward -n yolo1 pod/<yolo-pod-1> 18081:8080
```

In another terminal:

```bash
cd ~/Yolo-k8s
./load-generator/run_load_local.sh 600 --percent-load 10 --api-url http://127.0.0.1:18081 --max-workers-per-instance 10
```

Example for `3` instances at the same `10%` load per instance:

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=3
kubectl rollout status deployment/yolo-inference -n yolo1

kubectl get pods -n yolo1 -l app=yolo
kubectl port-forward -n yolo1 pod/<yolo-pod-1> 18081:8080
kubectl port-forward -n yolo1 pod/<yolo-pod-2> 18082:8080
kubectl port-forward -n yolo1 pod/<yolo-pod-3> 18083:8080
```

In another terminal:

```bash
cd ~/Yolo-k8s
./load-generator/run_load_local.sh 600 --percent-load 10 --api-url http://127.0.0.1:18081 --api-url http://127.0.0.1:18082 --api-url http://127.0.0.1:18083 --max-workers-per-instance 10
```

Example for `3` instances with different load per instance:

```bash
cd ~/Yolo-k8s
./load-generator/run_load_local.sh 600 --percent-loads 10,20,30 --api-url http://127.0.0.1:18081 --api-url http://127.0.0.1:18082 --api-url http://127.0.0.1:18083 --max-workers-per-instance 10
```

### Stop the load

For local-terminal mode, stop the run with `Ctrl-C` in the terminal running `run_load_local.sh`.

If you stop the port-forward too:

```bash
Ctrl-C
```

in the port-forward terminal is enough.

### Watch GPU

```bash
nvidia-smi dmon -s u -d 1
```

## Optional: In-Cluster Job Mode

Use this only if you explicitly want Kubernetes Job pods to generate load.

```bash
cd ~/Yolo-k8s
./load-generator/run_load_job.sh <duration-seconds> [parallelism] [workers] [image-size]
./load-generator/run_load_job.sh <duration-seconds> --percent-load <1-100> [--instance-count N] [--max-parallelism N] [--max-workers N] [--image-size PX]
```

Important difference:

- `run_load_job.sh` creates `yolo-load-*` pods
- `run_load_local.sh` does not create any extra pods

## Optional: Automatic Ramp

If you ever want a sequential percentage ramp again:

```bash
cd ~/Yolo-k8s
./load-generator/run_load_ramp.sh 600
```

That mode is optional and is not needed for the manual workflow above.

## Notes

- For multi-replica local testing, target pod-specific port-forwards, not a single service port-forward.
- `--percent-load` applies the same percentage to every targeted pod.
- `--percent-loads` lets you vary the percentage per targeted pod in one run.
- `run_load_local.sh` uses the repo copy of `load-client.py`, so script changes take effect immediately.
