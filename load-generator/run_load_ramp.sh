#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 5 ]]; then
  echo "usage: $0 [duration-seconds] [max-parallelism] [workers] [image-size] [step-percent]" >&2
  exit 1
fi

DURATION_SECONDS="${1:-600}"
MAX_PARALLELISM="${2:-10}"
WORKERS="${3:-8}"
IMAGE_SIZE="${4:-1280}"
STEP_PERCENT="${5:-10}"
NAMESPACE="yolo1"
API_URL="http://yolo-api.yolo1.svc.cluster.local:8080"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="/home/user/Yolo-k8s/load-generator/runs/${RUN_ID}"

mkdir -p "${RUN_DIR}"

if (( DURATION_SECONDS <= 0 )); then
  echo "duration-seconds must be > 0" >&2
  exit 1
fi

if (( MAX_PARALLELISM <= 0 )); then
  echo "max-parallelism must be > 0" >&2
  exit 1
fi

if (( WORKERS <= 0 )); then
  echo "workers must be > 0" >&2
  exit 1
fi

if (( IMAGE_SIZE <= 0 )); then
  echo "image-size must be > 0" >&2
  exit 1
fi

if (( STEP_PERCENT <= 0 || STEP_PERCENT > 100 )); then
  echo "step-percent must be in the range 1..100" >&2
  exit 1
fi

echo "Starting YOLO load ramp"
echo "Namespace      : ${NAMESPACE}"
echo "Duration/step  : ${DURATION_SECONDS}s"
echo "Max parallelism: ${MAX_PARALLELISM}"
echo "Workers/pod    : ${WORKERS}"
echo "Image size     : ${IMAGE_SIZE}"
echo "Step percent   : ${STEP_PERCENT}"
echo "Run dir        : ${RUN_DIR}"
echo
echo "Percentage is defined here as a fraction of max load-generator parallelism."
echo "Example with max-parallelism=${MAX_PARALLELISM}: 10% => 1 pod, 100% => ${MAX_PARALLELISM} pods."
echo

for PERCENT in $(seq "${STEP_PERCENT}" "${STEP_PERCENT}" 100); do
  PARALLELISM=$(( (PERCENT * MAX_PARALLELISM + 99) / 100 ))
  if (( PARALLELISM < 1 )); then
    PARALLELISM=1
  fi

  JOB_NAME="yolo-load-p${PERCENT}-${RUN_ID,,}"
  WAIT_TIMEOUT="$(( DURATION_SECONDS + 300 ))s"
  LOG_FILE="${RUN_DIR}/${PERCENT}pct.log"

  echo "============================================================"
  echo "Step ${PERCENT}%"
  echo "Parallelism: ${PARALLELISM}"
  echo "Job name   : ${JOB_NAME}"
  echo "Log file   : ${LOG_FILE}"
  echo "Started at : $(date -u +%Y-%m-%dT%H:%M:%SZ)"

  kubectl create -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: yolo-load
    workload-mode: ramp
    load-percent: "${PERCENT}"
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
        workload-mode: ramp
        load-percent: "${PERCENT}"
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

  if ! kubectl wait --for=condition=complete --timeout="${WAIT_TIMEOUT}" "job/${JOB_NAME}" -n "${NAMESPACE}"; then
    echo "Job ${JOB_NAME} did not complete successfully" >&2
    kubectl describe job "${JOB_NAME}" -n "${NAMESPACE}" || true
    kubectl get pods -n "${NAMESPACE}" -l "job-name=${JOB_NAME}" -o wide || true
    kubectl logs -n "${NAMESPACE}" -l "job-name=${JOB_NAME}" --all-containers=true --prefix=true || true
    exit 1
  fi

  kubectl logs -n "${NAMESPACE}" -l "job-name=${JOB_NAME}" --all-containers=true --prefix=true > "${LOG_FILE}" || true
  kubectl get pods -n "${NAMESPACE}" -l "job-name=${JOB_NAME}" -o wide > "${RUN_DIR}/${PERCENT}pct-pods.txt" || true

  echo "Completed at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
done

echo "Ramp complete. Logs saved under ${RUN_DIR}"
