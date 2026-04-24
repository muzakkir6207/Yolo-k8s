# YOLO Load Testing Test Cases

This document defines the recommended end-to-end test cases for Yolo load testing in `yolo1`.

It is written for the current preferred workflow:

- generate load from a local terminal
- do not create extra `yolo-load-*` pods
- target each `yolo-inference` pod explicitly with its own port-forward

Use this document when you want to run the full series of experiments and record results consistently.

## Goal

The objective is to measure how the Yolo application behaves when:

- the number of `yolo-inference` instances changes
- the load per instance changes
- the load distribution across instances is either uniform or intentionally different

This lets you study:

- GPU utilization
- per-run throughput
- request errors
- scaling behavior as replicas increase
- behavior under balanced and unbalanced per-instance load

## Scripts Used

The following repo files are the active entrypoints for this workflow:

- [LOAD_GENERATION_GUIDE.md](LOAD_GENERATION_GUIDE.md)
- [load-generator/run_load_local.sh](load-generator/run_load_local.sh)
- [load-generator/load-client.py](load-generator/load-client.py)

This document assumes you are using `run_load_local.sh`.

## Test Rules

Use these rules for the entire series:

1. Run one test case at a time.
2. Keep the test duration fixed at `600` seconds unless you intentionally change it.
3. For multi-instance tests, do not use a single service port-forward to `svc/yolo-api`.
4. For multi-instance tests, port-forward each pod separately and pass one `--api-url` per pod.
5. Use a fresh local port range for each new test group when possible, for example `19081`, `19082`, `19083`.
6. Before starting load, verify every forwarded port with `/health`.
7. Keep `--max-workers-per-instance` fixed for a given experiment series so the percentages stay comparable.
8. Record both the requested load and the actual mapping printed by `run_load_local.sh`.

Recommended reference:

- duration: `600` seconds
- image size: `1280`
- max workers per instance: `10`

## Common Setup

### 1. Move to the repo

```bash
cd ~/Yolo-k8s
```

### 2. Scale the inference deployment

Example for `3` replicas:

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=3
kubectl rollout status deployment/yolo-inference -n yolo1
kubectl get pods -n yolo1 -l app=yolo
```

### 3. Choose pod names

Copy the real pod names from:

```bash
kubectl get pods -n yolo1 -l app=yolo
```

Example variable assignment:

```bash
POD1="yolo-inference-xxxx"
POD2="yolo-inference-yyyy"
POD3="yolo-inference-zzzz"
```

### 4. Clear old local forwards

If you suspect stale forwards, clean them first:

```bash
pkill -f "kubectl port-forward --address 127.0.0.1 -n yolo1 pod/yolo-inference" || true
```

### 5. Start one port-forward per pod

Example for `3` replicas:

```bash
kubectl port-forward --address 127.0.0.1 -n yolo1 pod/$POD1 19081:8080 &
kubectl port-forward --address 127.0.0.1 -n yolo1 pod/$POD2 19082:8080 &
kubectl port-forward --address 127.0.0.1 -n yolo1 pod/$POD3 19083:8080 &
wait
```

### 6. Verify every forwarded pod

Run these in another terminal before starting load:

```bash
curl -sS http://127.0.0.1:19081/health
curl -sS http://127.0.0.1:19082/health
curl -sS http://127.0.0.1:19083/health
```

Only proceed when every target responds.

### 7. Watch GPU

```bash
nvidia-smi dmon -s u -d 1
```

## Test Matrix

Use the following cases as the standard series.

| Test Case | Replicas | Load Type | Description |
| --- | --- | --- | --- |
| `TC-00` | `0` or idle | none | Baseline idle GPU measurement |
| `TC-10` | `1` | uniform | Single-instance load sweep |
| `TC-20` | `2` | uniform | Two-instance load sweep |
| `TC-30` | `3` | uniform | Three-instance load sweep |
| `TC-40` | `2` | varied | Two-instance asymmetric load |
| `TC-50` | `3` | varied | Three-instance asymmetric load |

## TC-00: Idle Baseline

Purpose:

- capture idle GPU behavior before active load tests

Suggested setup:

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=0
kubectl rollout status deployment/yolo-inference -n yolo1
nvidia-smi dmon -s u -d 1 -c 60
```

Record:

- average idle `sm`
- average idle `mem`

## TC-10: One-Instance Uniform Sweep

Purpose:

- calibrate how one Yolo instance responds to increasing load

Setup:

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=1
kubectl rollout status deployment/yolo-inference -n yolo1
kubectl get pods -n yolo1 -l app=yolo
```

Port-forward:

```bash
POD1="yolo-inference-xxxx"
kubectl port-forward --address 127.0.0.1 -n yolo1 pod/$POD1 19081:8080
```

Health check:

```bash
curl -sS http://127.0.0.1:19081/health
```

Run one cycle at a time. Keep the command the same and only change `PERCENT`.

Allowed values for the sweep:

- `10`, `20`, `30`, `40`, `50`, `60`, `70`, `80`, `90`, `100`

Command pattern:

```bash
cd ~/Yolo-k8s/load-generator
PERCENT=100
./run_load_local.sh 600 --percent-load "$PERCENT" --api-url http://127.0.0.1:19081 --max-workers-per-instance 10
```

Expected behavior:

- one local client process
- one target pod
- no extra Kubernetes load pods

## TC-20: Two-Instance Uniform Sweep

Purpose:

- measure how two instances behave when the same load is applied to both

Setup:

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=2
kubectl rollout status deployment/yolo-inference -n yolo1
kubectl get pods -n yolo1 -l app=yolo
```

Port-forward:

```bash
POD1="yolo-inference-xxxx"
POD2="yolo-inference-yyyy"
kubectl port-forward --address 127.0.0.1 -n yolo1 pod/$POD1 19081:8080 &
kubectl port-forward --address 127.0.0.1 -n yolo1 pod/$POD2 19082:8080 &
wait
```

Health check:

```bash
curl -sS http://127.0.0.1:19081/health
curl -sS http://127.0.0.1:19082/health
```

Run one cycle at a time. Keep the command the same and only change `PERCENT`.

Allowed values for the sweep:

- `10`, `20`, `30`, `40`, `50`, `60`, `70`, `80`, `90`, `100`

Command pattern:

```bash
cd ~/Yolo-k8s/load-generator
PERCENT=100
./run_load_local.sh 600 --percent-load "$PERCENT" --api-url http://127.0.0.1:19081 --api-url http://127.0.0.1:19082 --max-workers-per-instance 10
```

Expected behavior:

- two local client processes
- one per target pod
- load is applied evenly across the two selected pods

## TC-30: Three-Instance Uniform Sweep

Purpose:

- measure behavior when three instances receive the same per-instance load

Setup:

```bash
kubectl scale deployment yolo-inference -n yolo1 --replicas=3
kubectl rollout status deployment/yolo-inference -n yolo1
kubectl get pods -n yolo1 -l app=yolo
```

Port-forward:

```bash
POD1="yolo-inference-xxxx"
POD2="yolo-inference-yyyy"
POD3="yolo-inference-zzzz"
kubectl port-forward --address 127.0.0.1 -n yolo1 pod/$POD1 19081:8080 &
kubectl port-forward --address 127.0.0.1 -n yolo1 pod/$POD2 19082:8080 &
kubectl port-forward --address 127.0.0.1 -n yolo1 pod/$POD3 19083:8080 &
wait
```

Health check:

```bash
curl -sS http://127.0.0.1:19081/health
curl -sS http://127.0.0.1:19082/health
curl -sS http://127.0.0.1:19083/health
```

Run one cycle at a time. Keep the command the same and only change `PERCENT`.

Allowed values for the sweep:

- `10`, `20`, `30`, `40`, `50`, `60`, `70`, `80`, `90`, `100`

Command pattern:

```bash
cd ~/Yolo-k8s/load-generator
PERCENT=100
./run_load_local.sh 600 --percent-load "$PERCENT" --api-url http://127.0.0.1:19081 --api-url http://127.0.0.1:19082 --api-url http://127.0.0.1:19083 --max-workers-per-instance 10
```

Expected behavior:

- three local client processes
- one per target pod
- aggregate GPU load should increase compared with the single-target service-forward approach

## TC-40: Two-Instance Varied Load

Purpose:

- measure behavior when two instances are loaded differently

Setup:

- use the same `2`-replica setup and port-forward pattern as `TC-20`

Run one cycle at a time. Keep the command the same and only change `LOAD_SPLITS`.

Suggested values:

- `10,20`
- `25,50`
- `50,100`

Command pattern:

```bash
cd ~/Yolo-k8s/load-generator
LOAD_SPLITS="50,100"
./run_load_local.sh 600 --percent-loads "$LOAD_SPLITS" --api-url http://127.0.0.1:19081 --api-url http://127.0.0.1:19082 --max-workers-per-instance 10
```

Expected behavior:

- pod 1 and pod 2 receive different request pressure
- total GPU impact depends on the combined requested load

## TC-50: Three-Instance Varied Load

Purpose:

- measure behavior when each instance is given a different load target

Setup:

- use the same `3`-replica setup and port-forward pattern as `TC-30`

Run one cycle at a time. Keep the command the same and only change `LOAD_SPLITS`.

Suggested values:

- `10,20,30`
- `25,50,75`
- `50,75,100`

Command pattern:

```bash
cd ~/Yolo-k8s/load-generator
LOAD_SPLITS="50,75,100"
./run_load_local.sh 600 --percent-loads "$LOAD_SPLITS" --api-url http://127.0.0.1:19081 --api-url http://127.0.0.1:19082 --api-url http://127.0.0.1:19083 --max-workers-per-instance 10
```

Expected behavior:

- each targeted pod receives its own requested load
- this is the most useful case when you want to study imbalance across replicas

## Recording Results

For each run, record at least:

- test case ID
- replica count
- local target ports
- requested load or requested per-target loads
- actual worker mapping printed by the script
- average GPU `sm`
- average GPU `mem`
- total requests
- total errors
- average QPS
- notes about failures, restarts, or unusual latency

Suggested result table:

| Test Case | Replicas | Load | Ports | Avg GPU SM | Avg GPU MEM | Requests | Errors | Avg QPS | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Stop and Cleanup

Stop the running load:

- press `Ctrl-C` in the terminal running `run_load_local.sh`

Stop local port-forwards:

- press `Ctrl-C` in the port-forward terminal
- or terminate the background jobs from that shell

Optional cleanup:

```bash
pkill -f "kubectl port-forward --address 127.0.0.1 -n yolo1 pod/yolo-inference" || true
kubectl scale deployment yolo-inference -n yolo1 --replicas=0
kubectl rollout status deployment/yolo-inference -n yolo1
```

## Troubleshooting

### `Connection refused`

This usually means:

- the port-forward is not running
- the port-forward failed to bind
- the pod changed and you are forwarding an old pod name
- the local URL does not match the bound address or port

Check:

```bash
curl -sS http://127.0.0.1:<port>/health
```

### `address already in use`

This means the chosen local port is already occupied.

Fix:

- kill stale port-forwards
- choose a fresh local port range such as `19081+`

### Only one pod gets loaded

This happens when you use a single service port-forward such as:

```bash
kubectl port-forward -n yolo1 svc/yolo-api 18080:8080
```

For multi-instance experiments, use one port-forward per pod and pass multiple `--api-url` values.

### Bash errors like `No such file or directory` after typing `<P>` or `<N>`

Do not type placeholder text with angle brackets literally.

Wrong:

```bash
./run_load_local.sh 600 --percent-load <P>
```

Correct:

```bash
./run_load_local.sh 600 --percent-load 20
```

## Recommended Execution Order

If you want to run the complete series from simplest to most complex, use:

1. `TC-00`
2. `TC-10`
3. `TC-20`
4. `TC-30`
5. `TC-40`
6. `TC-50`

That order helps you validate:

- baseline first
- single-instance calibration second
- replica scaling next
- asymmetric load last
