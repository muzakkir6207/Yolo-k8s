#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  run_load_job.sh <duration-seconds> [parallelism] [workers] [image-size]
  run_load_job.sh <duration-seconds> --percent-load <1-100> [--instance-count N] [--max-parallelism N] [--max-workers N] [--image-size PX]

examples:
  ./load-generator/run_load_job.sh 600
  ./load-generator/run_load_job.sh 600 2 8 1280
  ./load-generator/run_load_job.sh 600 --percent-load 10 --instance-count 1
  ./load-generator/run_load_job.sh 600 --percent-load 10 --instance-count 2 --max-parallelism 1 --max-workers 10
  ./load-generator/run_load_job.sh 600 --percent-load 22 --instance-count 3 --max-parallelism 1 --max-workers 10
EOF
}

require_positive_int() {
  local name="$1"
  local value="$2"

  if [[ ! "${value}" =~ ^[0-9]+$ ]] || (( value <= 0 )); then
    echo "${name} must be a positive integer" >&2
    exit 1
  fi
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

DURATION_SECONDS="$1"
shift

PARALLELISM=""
WORKERS=""
IMAGE_SIZE="1280"
PERCENT_LOAD=""
INSTANCE_COUNT=""
MAX_PARALLELISM="10"
MAX_WORKERS="8"
API_URL="http://yolo-api.yolo1.svc.cluster.local:8080"

LEGACY_ARGS=()
while [[ $# -gt 0 && "$1" != --* ]]; do
  LEGACY_ARGS+=("$1")
  shift
done

case "${#LEGACY_ARGS[@]}" in
  0)
    ;;
  1)
    PARALLELISM="${LEGACY_ARGS[0]}"
    ;;
  2)
    PARALLELISM="${LEGACY_ARGS[0]}"
    WORKERS="${LEGACY_ARGS[1]}"
    ;;
  3)
    PARALLELISM="${LEGACY_ARGS[0]}"
    WORKERS="${LEGACY_ARGS[1]}"
    IMAGE_SIZE="${LEGACY_ARGS[2]}"
    ;;
  *)
    usage
    exit 1
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --percent-load)
      PERCENT_LOAD="${2:-}"
      shift 2
      ;;
    --max-parallelism)
      MAX_PARALLELISM="${2:-}"
      shift 2
      ;;
    --max-workers)
      MAX_WORKERS="${2:-}"
      shift 2
      ;;
    --instance-count)
      INSTANCE_COUNT="${2:-}"
      shift 2
      ;;
    --parallelism)
      PARALLELISM="${2:-}"
      shift 2
      ;;
    --workers)
      WORKERS="${2:-}"
      shift 2
      ;;
    --image-size)
      IMAGE_SIZE="${2:-}"
      shift 2
      ;;
    --api-url)
      API_URL="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_positive_int "duration-seconds" "${DURATION_SECONDS}"
require_positive_int "image-size" "${IMAGE_SIZE}"

if [[ -n "${PERCENT_LOAD}" ]]; then
  require_positive_int "percent-load" "${PERCENT_LOAD}"
  require_positive_int "max-parallelism" "${MAX_PARALLELISM}"
  require_positive_int "max-workers" "${MAX_WORKERS}"

  if (( PERCENT_LOAD > 100 )); then
    echo "percent-load must be in the range 1..100" >&2
    exit 1
  fi

  if [[ -n "${PARALLELISM}" || -n "${WORKERS}" ]]; then
    echo "--percent-load cannot be combined with explicit parallelism/workers values" >&2
    exit 1
  fi

  if [[ -z "${INSTANCE_COUNT}" ]]; then
    INSTANCE_COUNT="$(kubectl get deployment yolo-inference -n yolo1 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    if [[ -z "${INSTANCE_COUNT}" ]]; then
      echo "could not detect ready yolo-inference replicas; use --instance-count explicitly" >&2
      exit 1
    fi
  fi

  require_positive_int "instance-count" "${INSTANCE_COUNT}"

  REFERENCE_UNITS_PER_INSTANCE=$(( MAX_PARALLELISM * MAX_WORKERS ))
  REFERENCE_UNITS=$(( INSTANCE_COUNT * REFERENCE_UNITS_PER_INSTANCE ))
  TARGET_UNITS=$(( (PERCENT_LOAD * REFERENCE_UNITS + 50) / 100 ))
  if (( TARGET_UNITS < 1 )); then
    TARGET_UNITS=1
  fi

  PARALLELISM_LIMIT=$(( MAX_PARALLELISM * INSTANCE_COUNT ))
  WORKERS_LIMIT=${MAX_WORKERS}
  BEST_PARALLELISM=1
  BEST_WORKERS=1
  BEST_UNITS=1
  BEST_DIFF=${REFERENCE_UNITS}

  for (( candidate_parallelism = 1; candidate_parallelism <= PARALLELISM_LIMIT; candidate_parallelism++ )); do
    for (( candidate_workers = 1; candidate_workers <= WORKERS_LIMIT; candidate_workers++ )); do
      candidate_units=$(( candidate_parallelism * candidate_workers ))
      candidate_diff=$(( candidate_units - TARGET_UNITS ))
      if (( candidate_diff < 0 )); then
        candidate_diff=$(( -candidate_diff ))
      fi

      if (( candidate_diff < BEST_DIFF )) \
        || (( candidate_diff == BEST_DIFF && candidate_workers < BEST_WORKERS )) \
        || (( candidate_diff == BEST_DIFF && candidate_workers == BEST_WORKERS && candidate_parallelism < BEST_PARALLELISM )); then
        BEST_PARALLELISM=${candidate_parallelism}
        BEST_WORKERS=${candidate_workers}
        BEST_UNITS=${candidate_units}
        BEST_DIFF=${candidate_diff}
      fi
    done
  done

  PARALLELISM="${BEST_PARALLELISM}"
  WORKERS="${BEST_WORKERS}"
  ACTUAL_PERCENT="$(awk -v units="${BEST_UNITS}" -v ref="${REFERENCE_UNITS}" 'BEGIN { printf "%.1f", (units / ref) * 100 }')"
else
  PARALLELISM="${PARALLELISM:-1}"
  WORKERS="${WORKERS:-8}"
  require_positive_int "parallelism" "${PARALLELISM}"
  require_positive_int "workers" "${WORKERS}"
  INSTANCE_COUNT="${INSTANCE_COUNT:-manual}"
  ACTUAL_PERCENT=""
fi

JOB_NAME="yolo-load-$(date +%s)"

kubectl create -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: yolo1
  labels:
    app: yolo-load
    workload-mode: one-shot
    load-percent: "${PERCENT_LOAD:-manual}"
spec:
  completions: ${PARALLELISM}
  parallelism: ${PARALLELISM}
  backoffLimit: 0
  ttlSecondsAfterFinished: 120
  activeDeadlineSeconds: $((DURATION_SECONDS + 180))
  template:
    metadata:
      labels:
        app: yolo-load
        workload-mode: one-shot
        load-percent: "${PERCENT_LOAD:-manual}"
    spec:
      restartPolicy: Never
      containers:
      - name: load-generator
        image: muzakkir6207/yolo-load-generator:v1
        imagePullPolicy: IfNotPresent
        command: ["python", "/workspace/load-generator/load-client.py"]
        args:
          - "--api-url=${API_URL}"
          - "--workers=${WORKERS}"
          - "--image-size=${IMAGE_SIZE}"
          - "--duration=${DURATION_SECONDS}"
        volumeMounts:
        - name: load-generator-src
          mountPath: /workspace/load-generator
          readOnly: true
        resources: {}
      volumes:
      - name: load-generator-src
        hostPath:
          path: /home/user/Yolo-k8s/load-generator
          type: Directory
YAML

echo "created job: ${JOB_NAME}"
if [[ -n "${PERCENT_LOAD}" ]]; then
  echo "requested load per instance : ${PERCENT_LOAD}%"
  echo "instance count              : ${INSTANCE_COUNT} ready yolo-inference replicas"
  echo "reference load per instance : ${MAX_PARALLELISM} pods x ${MAX_WORKERS} workers = ${REFERENCE_UNITS_PER_INSTANCE} worker-units"
  echo "total reference load        : ${INSTANCE_COUNT} x ${REFERENCE_UNITS_PER_INSTANCE} = ${REFERENCE_UNITS} worker-units"
  echo "actual total mapping        : ${PARALLELISM} pods x ${WORKERS} workers = ${ACTUAL_PERCENT}% of scaled reference"
else
  echo "manual mapping : ${PARALLELISM} pods x ${WORKERS} workers"
fi
echo "duration       : ${DURATION_SECONDS}s"
echo "image size     : ${IMAGE_SIZE}"
echo "watch          : kubectl get pods -n yolo1 -l job-name=${JOB_NAME} -w"
echo "logs           : kubectl logs -n yolo1 -l job-name=${JOB_NAME} --all-containers=true -f"
