#!/usr/bin/env bash
# Atualiza o serviço ECS para a imagem recém-publicada no ECR.
set -euo pipefail

: "${AWS_DEFAULT_REGION:?}"
: "${ECR_REPOSITORY_URI:?}"
: "${ECS_CLUSTER:?}"
: "${ECS_SERVICE:?}"
: "${IMAGE_TAG:?}"

export IMAGE="${ECR_REPOSITORY_URI}:${IMAGE_TAG}"

echo "==> Forçando novo deploy no ECS: ${ECS_CLUSTER}/${ECS_SERVICE}"
echo "    imagem=${IMAGE}"

TASK_FAMILY=$(aws ecs describe-services \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --query "services[0].taskDefinition" \
  --output text | awk -F/ '{print $NF}' | sed 's/:.*//')

aws ecs describe-task-definition \
  --task-definition "${TASK_FAMILY}" \
  --query "taskDefinition" > /tmp/task-def.json

python3 <<'PY'
import json, os

with open("/tmp/task-def.json") as f:
    td = json.load(f)

image = os.environ["IMAGE"]
keep = [
    "family", "taskRoleArn", "executionRoleArn", "networkMode", "containerDefinitions",
    "volumes", "placementConstraints", "requiresCompatibilities", "cpu", "memory",
    "runtimePlatform", "proxyConfiguration", "inferenceAccelerators", "ephemeralStorage",
]
out = {k: td[k] for k in keep if k in td}
for c in out.get("containerDefinitions", []):
    if c.get("name") == "status-api":
        c["image"] = image

with open("/tmp/new-task-def.json", "w") as f:
    json.dump(out, f)
PY

NEW_ARN=$(aws ecs register-task-definition \
  --cli-input-json file:///tmp/new-task-def.json \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

aws ecs update-service \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --task-definition "${NEW_ARN}" \
  --force-new-deployment \
  --desired-count 1 \
  >/dev/null

echo "==> Aguardando estabilização do serviço..."
aws ecs wait services-stable \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}"

echo "Deploy ECS concluído."
