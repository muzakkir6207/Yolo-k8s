# YOLO Load Testing Per Namespace

This document defines the recommended end-to-end test cases for Yolo load testing when each instance runs in a different namespace.

Use this when your model is:

- one `yolo-inference` instance per namespace
- each namespace represents an isolated user/tenant (for example `transparent-user-*` or `yolo-*`)
- total pressure on the server increases by adding more namespaces, not by increasing replicas in one namespace

## Goal

Measure how the system behaves when:

- the number of namespaces with active Yolo instances increases
- each namespace gets the same load or different load

This lets you study:

- aggregate GPU utilization
- throughput growth as namespace count increases
- request errors and saturation points
- fairness/imbalance when namespace loads differ

## Scripts Used

The active entrypoints for this workflow are:

- [LOAD_GENERATION_GUIDE.md](LOAD_GENERATION_GUIDE.md)
- [load-generator/run_load_local.sh](load-generator/run_load_local.sh)
- [load-generator/load-client.py](load-generator/load-client.py)

This guide assumes local-terminal load (`run_load_local.sh`) and no extra `yolo-load-*` pods.

## Test Rules

Use these rules for the entire test series:

1. Keep `yolo-inference` at `1` replica in each test namespace.
2. Change namespace count to scale load (for example `1 -> 2 -> 3` namespaces).
3. Run one test case at a time.
4. Keep test duration fixed at `600` seconds unless you intentionally change it.
5. Create one local endpoint per namespace (recommended: port-forward `svc/yolo-api` in each namespace).
6. Verify `/health` for every local endpoint before starting load.
7. Keep worker count, image size, model, and delay fixed within a comparison series.
8. Record requested load and actual worker mapping printed by `run_load_local.sh`.
9. For single-namespace runs, pass `--instance-count 1` to avoid relying on auto-detection from `-n yolo1`.

Recommended calibrated baseline for one namespace:

- model: `yolov8x.pt`
- duration: `300` to `600`
- workers: `5`
- image size: `1536`
- worker delay: `0ms`

For multi-namespace uniform runs, map this baseline with:

- `--percent-load 100`
- `--max-workers-per-instance 5`
- `--image-size 1536`
- `--worker-delay-ms 0`

## Common Setup

### 1. Move to the repo

```bash
cd ~/Yolo-k8s
```

### 2. Define namespace names for the current run

Use your real namespace names. Example:

```bash
NS1="transparent-user-1"   # or yolo-1
NS2="transparent-user-2"   # or yolo-2
NS3="transparent-user-3"   # or yolo-3
NS4="transparent-user-4"
NS5="transparent-user-5"
```

### 3. Ensure one ready instance per namespace

Run this only for namespaces involved in the current case.

```bash
for ns in "$NS1" "$NS2" "$NS3"; do
  kubectl scale deployment yolo-inference -n "$ns" --replicas=1
  kubectl rollout status deployment/yolo-inference -n "$ns"
  kubectl get pods -n "$ns" -l app=yolo
done
```

### 3b. Pin the model used for baseline runs

```bash
kubectl set env deployment/yolo-inference -n "$NS1" YOLO_MODEL=yolov8x.pt
kubectl rollout status deployment/yolo-inference -n "$NS1"
```

Repeat for other namespaces when they participate in the run.

### 4. Clear old local forwards (optional)

```bash
pkill -f "kubectl port-forward --address 127.0.0.1 .*svc/yolo-api" || true
```

### 5. Start one port-forward per namespace

Example for 3 namespaces:

```bash
kubectl port-forward --address 127.0.0.1 -n "$NS1" svc/yolo-api 19181:8080 &
kubectl port-forward --address 127.0.0.1 -n "$NS2" svc/yolo-api 19182:8080 &
kubectl port-forward --address 127.0.0.1 -n "$NS3" svc/yolo-api 19183:8080 &
wait
```

### 6. Verify every forwarded endpoint

```bash
curl -sS http://127.0.0.1:19181/health
curl -sS http://127.0.0.1:19182/health
curl -sS http://127.0.0.1:19183/health
```

Only proceed if every endpoint responds healthy.

### 7. Watch GPU

```bash
nvidia-smi dmon -s u -d 1
```

For consistency checks, use averaged SM instead of single-line values:

```bash
nvidia-smi dmon -s u -d 1 -c 120 | awk '($1 ~ /^[0-9]+$/){sum+=$2;n++} END{if(n) print "avg sm% =",sum/n}'
```

## Test Matrix

| Test Case | Active Namespaces | Load Type | Description |
| --- | --- | --- | --- |
| `TC-NS-00` | `0` or idle | none | Baseline idle GPU measurement |
| `TC-NS-10` | `1` | uniform | Single-namespace load sweep |
| `TC-NS-20` | `2` | uniform | Two-namespace uniform sweep |
| `TC-NS-30` | `3` | uniform | Three-namespace uniform sweep |
| `TC-NS-40` | `4` | uniform | Four-namespace uniform sweep |
| `TC-NS-50` | `5` | uniform | Five-namespace uniform sweep |
| `TC-NS-60` | `2` | varied | Two-namespace asymmetric load |
| `TC-NS-70` | `3` | varied | Three-namespace asymmetric load |

## TC-NS-00: Idle Baseline

Purpose:

- capture idle GPU behavior before active load tests

Suggested setup:

```bash
nvidia-smi dmon -s u -d 1 -c 60
```

Record:

- average idle `sm`
- average idle `mem`

## TC-NS-10: One Namespace Uniform Sweep

Purpose:

- calibrate one namespace instance against increasing load

Setup:

```bash
kubectl scale deployment yolo-inference -n "$NS1" --replicas=1
kubectl rollout status deployment/yolo-inference -n "$NS1"
kubectl get pods -n "$NS1" -l app=yolo
kubectl port-forward --address 127.0.0.1 -n "$NS1" svc/yolo-api 19181:8080
```

Health check:

```bash
curl -sS http://127.0.0.1:19181/health
```

Allowed sweep values:

- `10`, `20`, `30`, `40`, `50`, `60`, `70`, `80`, `90`, `100`

Recommended baseline command (validated):

```bash
cd ~/Yolo-k8s/load-generator
./run_load_local.sh 300 5 1536 \
  --api-url http://127.0.0.1:19181 \
  --worker-delay-ms 0
```

## TC-NS-20: Two Namespaces Uniform Sweep

Purpose:

- measure uniform load behavior across two isolated namespaces

Setup and forwards:

```bash
for ns in "$NS1" "$NS2"; do
  kubectl scale deployment yolo-inference -n "$ns" --replicas=1
  kubectl rollout status deployment/yolo-inference -n "$ns"
done

kubectl port-forward --address 127.0.0.1 -n "$NS1" svc/yolo-api 19181:8080 &
kubectl port-forward --address 127.0.0.1 -n "$NS2" svc/yolo-api 19182:8080 &
wait
```

Health check:

```bash
curl -sS http://127.0.0.1:19181/health
curl -sS http://127.0.0.1:19182/health
```

Recommended command pattern:

```bash
cd ~/Yolo-k8s/load-generator
./run_load_local.sh 600 \
  --percent-load 100 \
  --instance-count 2 \
  --api-url http://127.0.0.1:19181 \
  --api-url http://127.0.0.1:19182 \
  --max-workers-per-instance 5 \
  --image-size 1536 \
  --worker-delay-ms 0
```

## TC-NS-30: Three Namespaces Uniform Sweep

Purpose:

- measure uniform load behavior across three namespaces

Recommended command pattern:

```bash
cd ~/Yolo-k8s/load-generator
./run_load_local.sh 600 \
  --percent-load 100 \
  --instance-count 3 \
  --api-url http://127.0.0.1:19181 \
  --api-url http://127.0.0.1:19182 \
  --api-url http://127.0.0.1:19183 \
  --max-workers-per-instance 5 \
  --image-size 1536 \
  --worker-delay-ms 0
```

## TC-NS-40: Four Namespaces Uniform Sweep

Purpose:

- measure uniform load behavior across four namespaces

Recommended command pattern:

```bash
cd ~/Yolo-k8s/load-generator
./run_load_local.sh 600 \
  --percent-load 100 \
  --instance-count 4 \
  --api-url http://127.0.0.1:19181 \
  --api-url http://127.0.0.1:19182 \
  --api-url http://127.0.0.1:19183 \
  --api-url http://127.0.0.1:19184 \
  --max-workers-per-instance 5 \
  --image-size 1536 \
  --worker-delay-ms 0
```

## TC-NS-50: Five Namespaces Uniform Sweep

Purpose:

- measure uniform load behavior across five namespaces

Recommended command pattern:

```bash
cd ~/Yolo-k8s/load-generator
./run_load_local.sh 600 \
  --percent-load 100 \
  --instance-count 5 \
  --api-url http://127.0.0.1:19181 \
  --api-url http://127.0.0.1:19182 \
  --api-url http://127.0.0.1:19183 \
  --api-url http://127.0.0.1:19184 \
  --api-url http://127.0.0.1:19185 \
  --max-workers-per-instance 5 \
  --image-size 1536 \
  --worker-delay-ms 0
```

## TC-NS-60: Two Namespaces Varied Load

Purpose:

- compare behavior when two namespaces receive different load

Suggested values:

- `60,80`
- `80,100`
- `100,100`

Recommended command pattern:

```bash
cd ~/Yolo-k8s/load-generator
./run_load_local.sh 600 \
  --percent-loads 60,80 \
  --instance-count 2 \
  --api-url http://127.0.0.1:19181 \
  --api-url http://127.0.0.1:19182 \
  --max-workers-per-instance 5 \
  --image-size 1536 \
  --worker-delay-ms 0
```

## TC-NS-70: Three Namespaces Varied Load

Purpose:

- compare behavior when each namespace gets a different load

Suggested values:

- `60,80,100`
- `80,100,100`
- `100,100,100`

Recommended command pattern:

```bash
cd ~/Yolo-k8s/load-generator
./run_load_local.sh 600 \
  --percent-loads 60,80,100 \
  --instance-count 3 \
  --api-url http://127.0.0.1:19181 \
  --api-url http://127.0.0.1:19182 \
  --api-url http://127.0.0.1:19183 \
  --max-workers-per-instance 5 \
  --image-size 1536 \
  --worker-delay-ms 0
```

## Recording Results

For each run, record at least:

- test case ID
- active namespace list
- local target ports
- requested load (uniform or per-namespace list)
- actual mapping printed by the script
- average GPU `sm`
- average GPU `mem`
- total requests
- total errors
- average QPS
- notes about timeouts/restarts

Suggested table:

| Test Case | Namespaces | Load | Ports | Avg GPU SM | Avg GPU MEM | Requests | Errors | Avg QPS | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Stop and Cleanup

Stop load:

- `Ctrl-C` in the terminal running `run_load_local.sh`

Stop port-forwards:

- `Ctrl-C` in the port-forward terminal
- or terminate background jobs from that shell

Optional cleanup:

```bash
pkill -f "kubectl port-forward --address 127.0.0.1 .*svc/yolo-api" || true
for ns in "$NS1" "$NS2" "$NS3" "$NS4" "$NS5"; do
  kubectl scale deployment yolo-inference -n "$ns" --replicas=0 || true
done
```

## Troubleshooting

### `Connection refused`

Usually means:

- corresponding port-forward is not running
- wrong local port
- target service or pod not ready in that namespace

Check:

```bash
curl -sS http://127.0.0.1:<port>/health
kubectl get pods -n <namespace> -l app=yolo
```

### Namespace not found

If you see namespace errors, validate names:

```bash
kubectl get ns | grep -E "yolo-|transparent-user-"
```

### Service not found in a namespace

Verify resources exist in each namespace:

```bash
kubectl get deployment yolo-inference -n <namespace>
kubectl get svc yolo-api -n <namespace>
```

### `address already in use`

Chosen local port is occupied.

Fix:

- stop stale forwards
- use a fresh range such as `19181+`

### Single-namespace baseline command

For one namespace, use the validated manual-workers command as the primary baseline:

```bash
./run_load_local.sh 300 5 1536 --api-url http://127.0.0.1:19181 --worker-delay-ms 0
```

If you prefer percent mode for single namespace, use the equivalent mapping:

```bash
./run_load_local.sh 600 --percent-load 100 --instance-count 1 --api-url http://127.0.0.1:19181 --max-workers-per-instance 5 --image-size 1536 --worker-delay-ms 0
```

### SM % looks noisy (0, 6, 13, 17...)

This is expected with 1-second GPU samples. Judge consistency by average, not single points:

```bash
nvidia-smi dmon -s u -d 1 -c 120 | awk '($1 ~ /^[0-9]+$/){sum+=$2;n++} END{if(n) print "avg sm% =",sum/n}'
```

## Recommended Execution Order

1. `TC-NS-00`
2. `TC-NS-10`
3. `TC-NS-20`
4. `TC-NS-30`
5. `TC-NS-40`
6. `TC-NS-50`
7. `TC-NS-60`
8. `TC-NS-70`

This order validates baseline first, then uniform namespace scaling, then asymmetric namespace load.
