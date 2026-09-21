#!/usr/bin/env bash
# Deploy do artefato no EC2 via S3 + SSM Run Command.
# Variáveis esperadas (pipeline):
#   AWS_DEFAULT_REGION, DEPLOY_BUCKET, EC2_INSTANCE_ID, ARTIFACT_PATH
set -euo pipefail

: "${AWS_DEFAULT_REGION:?}"
: "${DEPLOY_BUCKET:?}"
: "${EC2_INSTANCE_ID:?}"

ARTIFACT_PATH="${ARTIFACT_PATH:-artifacts/status-api-linux.tar.gz}"
S3_KEY="releases/status-api-$(date +%Y%m%d%H%M%S).tar.gz"
REMOTE_SCRIPT="scripts/remote-install.sh"

echo "==> Upload ${ARTIFACT_PATH} -> s3://${DEPLOY_BUCKET}/${S3_KEY}"
aws s3 cp "${ARTIFACT_PATH}" "s3://${DEPLOY_BUCKET}/${S3_KEY}"

# Envia também o script de instalação (idempotente)
aws s3 cp "${REMOTE_SCRIPT}" "s3://${DEPLOY_BUCKET}/scripts/remote-install.sh"

echo "==> Executando instalação via SSM em ${EC2_INSTANCE_ID}"
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "${EC2_INSTANCE_ID}" \
  --document-name "AWS-RunShellScript" \
  --comment "Deploy status-api" \
  --parameters "commands=[
    \"aws s3 cp s3://${DEPLOY_BUCKET}/scripts/remote-install.sh /tmp/remote-install.sh\",
    \"chmod +x /tmp/remote-install.sh\",
    \"DEPLOY_BUCKET=${DEPLOY_BUCKET} S3_KEY=${S3_KEY} /tmp/remote-install.sh\"
  ]" \
  --query "Command.CommandId" \
  --output text)

echo "SSM CommandId=${COMMAND_ID}"

# Aguarda conclusão
for i in $(seq 1 36); do
  STATUS=$(aws ssm get-command-invocation \
    --command-id "${COMMAND_ID}" \
    --instance-id "${EC2_INSTANCE_ID}" \
    --query "Status" \
    --output text 2>/dev/null || echo "Pending")

  echo "  status=${STATUS}"
  case "${STATUS}" in
    Success)
      aws ssm get-command-invocation \
        --command-id "${COMMAND_ID}" \
        --instance-id "${EC2_INSTANCE_ID}" \
        --query "StandardOutputContent" \
        --output text
      exit 0
      ;;
    Failed|Cancelled|TimedOut)
      aws ssm get-command-invocation \
        --command-id "${COMMAND_ID}" \
        --instance-id "${EC2_INSTANCE_ID}" \
        --query "[Status,StandardErrorContent,StandardOutputContent]" \
        --output text
      exit 1
      ;;
  esac
  sleep 5
done

echo "Timeout aguardando SSM"
exit 1
