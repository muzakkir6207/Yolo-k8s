#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  run_load_local.sh <duration-seconds> [workers] [image-size] [--worker-delay-ms MS]
  run_load_local.sh <duration-seconds> --percent-load <1-100> [--instance-count N] [--max-workers-per-instance N] [--image-size PX] [--api-url URL] [--worker-delay-ms MS]
  run_load_local.sh <duration-seconds> --percent-load <1-100> --api-url URL [--api-url URL ...] [--max-workers-per-instance N] [--image-size PX] [--worker-delay-ms MS]
  run_load_local.sh <duration-seconds> --percent-loads <P1,P2,...> --api-url URL [--api-url URL ...] [--max-workers-per-instance N] [--image-size PX] [--worker-delay-ms MS]

examples:
  ./load-generator/run_load_local.sh 600 1
  ./load-generator/run_load_local.sh 600 --percent-load 10 --instance-count 1 --max-workers-per-instance 10
  ./load-generator/run_load_local.sh 600 --percent-load 22 --instance-count 3 --max-workers-per-instance 10
  ./load-generator/run_load_local.sh 600 --percent-load 10 --api-url http://127.0.0.1:18081 --api-url http://127.0.0.1:18082
  ./load-generator/run_load_local.sh 600 --percent-loads 10,20,30 --api-url http://127.0.0.1:18081 --api-url http://127.0.0.1:18082 --api-url http://127.0.0.1:18083
  ./load-generator/run_load_local.sh 600 --percent-load 20 --api-url http://127.0.0.1:18081 --api-url http://127.0.0.1:18082 --max-workers-per-instance 10 --worker-delay-ms 250
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

require_nonnegative_int() {
  local name="$1"
  local value="$2"

  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    echo "${name} must be a non-negative integer" >&2
    exit 1
  fi
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  usage
  exit 0
fi

DURATION_SECONDS="$1"
shift

WORKERS=""
IMAGE_SIZE="1280"
PERCENT_LOAD=""
PERCENT_LOADS=""
INSTANCE_COUNT=""
MAX_WORKERS_PER_INSTANCE="10"
API_URL="http://127.0.0.1:18080"
API_URLS=()
WORKER_DELAY_MS="0"

LEGACY_ARGS=()
while [[ $# -gt 0 && "$1" != --* ]]; do
  LEGACY_ARGS+=("$1")
  shift
done

case "${#LEGACY_ARGS[@]}" in
  0)
    ;;
  1)
    WORKERS="${LEGACY_ARGS[0]}"
    ;;
  2)
    WORKERS="${LEGACY_ARGS[0]}"
    IMAGE_SIZE="${LEGACY_ARGS[1]}"
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
    --instance-count)
      INSTANCE_COUNT="${2:-}"
      shift 2
      ;;
    --percent-loads)
      PERCENT_LOADS="${2:-}"
      shift 2
      ;;
    --max-workers-per-instance)
      MAX_WORKERS_PER_INSTANCE="${2:-}"
      shift 2
      ;;
    --workers)
      WORKERS="${2:-}"
      shift 2
      ;;
    --worker-delay-ms)
      WORKER_DELAY_MS="${2:-}"
      shift 2
      ;;
    --image-size)
      IMAGE_SIZE="${2:-}"
      shift 2
      ;;
    --api-url)
      API_URL="${2:-}"
      API_URLS+=("${2:-}")
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
require_nonnegative_int "worker-delay-ms" "${WORKER_DELAY_MS}"

if [[ -n "${PERCENT_LOAD}" && -n "${PERCENT_LOADS}" ]]; then
  echo "--percent-load cannot be combined with --percent-loads" >&2
  exit 1
fi

if [[ "${#API_URLS[@]}" -eq 0 ]]; then
  API_URLS=("${API_URL}")
fi

parse_percent_loads() {
  local csv="$1"
  local -n out_array_ref="$2"
  local item=""

  IFS=',' read -r -a out_array_ref <<< "${csv}"
  if [[ "${#out_array_ref[@]}" -eq 0 ]]; then
    echo "percent-loads must contain at least one entry" >&2
    exit 1
  fi

  for item in "${out_array_ref[@]}"; do
    require_positive_int "percent-loads entry" "${item}"
    if (( item > 100 )); then
      echo "percent-loads entries must be in the range 1..100" >&2
      exit 1
    fi
  done
}

if [[ -n "${PERCENT_LOADS}" ]]; then
  LOAD_PERCENTS=()
  parse_percent_loads "${PERCENT_LOADS}" LOAD_PERCENTS

  if [[ -n "${WORKERS}" ]]; then
    echo "--percent-loads cannot be combined with explicit workers" >&2
    exit 1
  fi

  require_positive_int "max-workers-per-instance" "${MAX_WORKERS_PER_INSTANCE}"

  if [[ "${#API_URLS[@]}" -ne "${#LOAD_PERCENTS[@]}" ]]; then
    echo "number of --api-url values must match the number of percent-loads entries" >&2
    exit 1
  fi

  if [[ -n "${INSTANCE_COUNT}" ]]; then
    require_positive_int "instance-count" "${INSTANCE_COUNT}"
    if (( INSTANCE_COUNT != ${#API_URLS[@]} )); then
      echo "instance-count must match the number of --api-url values in multi-target mode" >&2
      exit 1
    fi
  else
    INSTANCE_COUNT="${#API_URLS[@]}"
  fi

  echo "running local load generator"
  echo "mode                        : per-target local endpoints"
  echo "instance count              : ${INSTANCE_COUNT}"
  echo "reference load per instance : ${MAX_WORKERS_PER_INSTANCE} workers"
  echo "duration                    : ${DURATION_SECONDS}s"
  echo "image size                  : ${IMAGE_SIZE}"
  echo "worker delay                : ${WORKER_DELAY_MS}ms"

  CHILD_PIDS=()
  cleanup() {
    trap - INT TERM
    if [[ "${#CHILD_PIDS[@]}" -gt 0 ]]; then
      echo "stopping local load generators" >&2
      kill "${CHILD_PIDS[@]}" 2>/dev/null || true
      wait "${CHILD_PIDS[@]}" 2>/dev/null || true
    fi
  }
  trap cleanup INT TERM

  for i in "${!API_URLS[@]}"; do
    workers_for_target=$(( (LOAD_PERCENTS[i] * MAX_WORKERS_PER_INSTANCE + 50) / 100 ))
    if (( workers_for_target < 1 )); then
      workers_for_target=1
    fi

    echo "target $((i + 1))                    : ${API_URLS[i]}"
    echo "requested load for target $((i + 1)) : ${LOAD_PERCENTS[i]}%"
    echo "actual mapping for target $((i + 1)) : 1 process x ${workers_for_target} workers"

    python3 /home/user/Yolo-k8s/load-generator/load-client.py \
      --api-url "${API_URLS[i]}" \
      --workers "${workers_for_target}" \
      --image-size "${IMAGE_SIZE}" \
      --duration "${DURATION_SECONDS}" \
      --worker-delay-ms "${WORKER_DELAY_MS}" &
    CHILD_PIDS+=("$!")
  done

  wait "${CHILD_PIDS[@]}"
  exit 0
fi

if [[ -n "${PERCENT_LOAD}" ]]; then
  require_positive_int "percent-load" "${PERCENT_LOAD}"
  require_positive_int "max-workers-per-instance" "${MAX_WORKERS_PER_INSTANCE}"

  if (( PERCENT_LOAD > 100 )); then
    echo "percent-load must be in the range 1..100" >&2
    exit 1
  fi

  if [[ -n "${WORKERS}" ]]; then
    echo "--percent-load cannot be combined with explicit workers" >&2
    exit 1
  fi

  if (( ${#API_URLS[@]} > 1 )); then
    LOAD_PERCENTS=()
    for (( i = 0; i < ${#API_URLS[@]}; i++ )); do
      LOAD_PERCENTS+=("${PERCENT_LOAD}")
    done

    if [[ -n "${INSTANCE_COUNT}" ]]; then
      require_positive_int "instance-count" "${INSTANCE_COUNT}"
      if (( INSTANCE_COUNT != ${#API_URLS[@]} )); then
        echo "instance-count must match the number of --api-url values in multi-target mode" >&2
        exit 1
      fi
    else
      INSTANCE_COUNT="${#API_URLS[@]}"
    fi

    echo "running local load generator"
    echo "mode                        : per-target local endpoints"
    echo "instance count              : ${INSTANCE_COUNT}"
    echo "reference load per instance : ${MAX_WORKERS_PER_INSTANCE} workers"
    echo "duration                    : ${DURATION_SECONDS}s"
    echo "image size                  : ${IMAGE_SIZE}"
    echo "worker delay                : ${WORKER_DELAY_MS}ms"

    CHILD_PIDS=()
    cleanup() {
      trap - INT TERM
      if [[ "${#CHILD_PIDS[@]}" -gt 0 ]]; then
        echo "stopping local load generators" >&2
        kill "${CHILD_PIDS[@]}" 2>/dev/null || true
        wait "${CHILD_PIDS[@]}" 2>/dev/null || true
      fi
    }
    trap cleanup INT TERM

    workers_for_target=$(( (PERCENT_LOAD * MAX_WORKERS_PER_INSTANCE + 50) / 100 ))
    if (( workers_for_target < 1 )); then
      workers_for_target=1
    fi

    for i in "${!API_URLS[@]}"; do
      echo "target $((i + 1))                    : ${API_URLS[i]}"
      echo "requested load for target $((i + 1)) : ${PERCENT_LOAD}%"
      echo "actual mapping for target $((i + 1)) : 1 process x ${workers_for_target} workers"

      python3 /home/user/Yolo-k8s/load-generator/load-client.py \
        --api-url "${API_URLS[i]}" \
        --workers "${workers_for_target}" \
        --image-size "${IMAGE_SIZE}" \
        --duration "${DURATION_SECONDS}" \
        --worker-delay-ms "${WORKER_DELAY_MS}" &
      CHILD_PIDS+=("$!")
    done

    wait "${CHILD_PIDS[@]}"
    exit 0
  fi

  if [[ -z "${INSTANCE_COUNT}" ]]; then
    INSTANCE_COUNT="$(kubectl get deployment yolo-inference -n yolo1 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    if [[ -z "${INSTANCE_COUNT}" ]]; then
      echo "could not detect ready yolo-inference replicas; use --instance-count explicitly" >&2
      exit 1
    fi
  fi

  require_positive_int "instance-count" "${INSTANCE_COUNT}"

  REFERENCE_UNITS_PER_INSTANCE="${MAX_WORKERS_PER_INSTANCE}"
  REFERENCE_UNITS=$(( INSTANCE_COUNT * REFERENCE_UNITS_PER_INSTANCE ))
  TARGET_UNITS=$(( (PERCENT_LOAD * REFERENCE_UNITS + 50) / 100 ))
  if (( TARGET_UNITS < 1 )); then
    TARGET_UNITS=1
  fi

  WORKERS="${TARGET_UNITS}"
  ACTUAL_PERCENT="$(awk -v units="${WORKERS}" -v ref="${REFERENCE_UNITS}" 'BEGIN { printf "%.1f", (units / ref) * 100 }')"
else
  WORKERS="${WORKERS:-1}"
  INSTANCE_COUNT="${INSTANCE_COUNT:-manual}"
  require_positive_int "workers" "${WORKERS}"
  ACTUAL_PERCENT=""
fi

echo "running local load generator"
if [[ -n "${PERCENT_LOAD}" ]]; then
  echo "requested load per instance : ${PERCENT_LOAD}%"
  echo "instance count              : ${INSTANCE_COUNT} ready yolo-inference replicas"
  echo "reference load per instance : ${REFERENCE_UNITS_PER_INSTANCE} workers"
  echo "total reference load        : ${INSTANCE_COUNT} x ${REFERENCE_UNITS_PER_INSTANCE} = ${REFERENCE_UNITS} worker-units"
  echo "actual local mapping        : 1 process x ${WORKERS} workers = ${ACTUAL_PERCENT}% of scaled reference"
  if (( INSTANCE_COUNT > 1 )) && [[ "${#API_URLS[@]}" -eq 1 ]]; then
    echo "warning                     : single api-url mode does not guarantee load is spread across all replicas" >&2
    echo "warning                     : for replica-aware local tests, port-forward each pod and pass multiple --api-url values" >&2
  fi
else
  echo "manual mapping              : 1 process x ${WORKERS} workers"
fi
echo "duration                    : ${DURATION_SECONDS}s"
echo "image size                  : ${IMAGE_SIZE}"
echo "worker delay                : ${WORKER_DELAY_MS}ms"
echo "api url                     : ${API_URL}"

exec python3 /home/user/Yolo-k8s/load-generator/load-client.py \
  --api-url "${API_URL}" \
  --workers "${WORKERS}" \
  --image-size "${IMAGE_SIZE}" \
  --duration "${DURATION_SECONDS}" \
  --worker-delay-ms "${WORKER_DELAY_MS}"
