#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 4 ]]; then
  echo "usage: $0 <duration-seconds> [parallelism] [workers] [image-size]" >&2
  exit 1
fi

DURATION_SECONDS="$1"
PARALLELISM="${2:-1}"
WORKERS="${3:-8}"
IMAGE_SIZE="${4:-1280}"
JOB_NAME="yolo-load-$(date +%s)"
API_URL="http://yolo-api.yolo1.svc.cluster.local:8080"

kubectl create -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: yolo1
  labels:
    app: yolo-load
    workload-mode: one-shot
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
echo "watch: kubectl get pods -n yolo1 -l job-name=${JOB_NAME} -w"
echo "logs : kubectl logs -n yolo1 -l job-name=${JOB_NAME} --all-containers=true -f"
