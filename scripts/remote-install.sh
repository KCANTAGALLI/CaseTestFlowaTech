#!/usr/bin/env bash
# Roda dentro do EC2 (via SSM). Extrai artefato, configura systemd e cron.
set -euo pipefail

: "${DEPLOY_BUCKET:?}"
: "${S3_KEY:?}"

APP_ROOT="/opt/status-api"
RELEASE_ID="$(date +%Y%m%d%H%M%S)"
RELEASE_DIR="${APP_ROOT}/releases/${RELEASE_ID}"

echo "[install] baixando s3://${DEPLOY_BUCKET}/${S3_KEY}"
mkdir -p "${RELEASE_DIR}"
aws s3 cp "s3://${DEPLOY_BUCKET}/${S3_KEY}" /tmp/status-api.tar.gz
tar -xzf /tmp/status-api.tar.gz -C "${RELEASE_DIR}"
chown -R deployxfer:deployxfer "${APP_ROOT}/releases"
chmod -R a+rX "${RELEASE_DIR}"

# Aponta "current" para o release novo
ln -sfn "${RELEASE_DIR}" "${APP_ROOT}/current"
chown -h deployxfer:deployxfer "${APP_ROOT}/current"

# Unit systemd (sempre regrava — pipeline é a fonte da verdade)
cat >/etc/systemd/system/status-api.service <<'UNIT'
[Unit]
Description=Status API (.NET)
After=network.target

[Service]
Type=simple
User=apprunner
Group=apprunner
WorkingDirectory=/opt/status-api/current
ExecStart=/usr/bin/dotnet /opt/status-api/current/StatusApi.dll
Restart=on-failure
RestartSec=5
Environment=ASPNETCORE_URLS=http://0.0.0.0:5000
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false
SyslogIdentifier=status-api

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable status-api.service
systemctl restart status-api.service

# Cron de start/stop do serviço (horário de Brasília via CRON_TZ)
# Complementa o Lambda que liga/desliga a instância.
cat >/etc/cron.d/status-api <<'CRON'
CRON_TZ=America/Sao_Paulo
SHELL=/bin/bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin

# Segunda a sexta: sobe às 09:00, desce às 18:00
0 9 * * 1-5 root /usr/bin/systemctl start status-api.service
0 18 * * 1-5 root /usr/bin/systemctl stop status-api.service
CRON
chmod 644 /etc/cron.d/status-api

# Health check rápido
sleep 3
if curl -sf http://127.0.0.1:5000/api/status | grep -q Healthy; then
  echo "[install] ok — /api/status = Healthy"
else
  echo "[install] aviso: endpoint ainda não respondeu Healthy"
  systemctl status status-api.service --no-pager || true
  journalctl -u status-api.service -n 40 --no-pager || true
  exit 1
fi
