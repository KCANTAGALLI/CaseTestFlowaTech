#!/usr/bin/env bash
# Gera o artefato Linux (publish self-contained opcional — aqui usamos framework-dependent)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/artifacts/linux"
APP_DIR="${ROOT_DIR}/src/StatusApi"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

dotnet publish "${APP_DIR}/StatusApi.csproj" \
  -c Release \
  -r linux-x64 \
  --self-contained false \
  -o "${OUT_DIR}"

# Empacota para upload no S3 / transferência
tar -C "${OUT_DIR}" -czf "${ROOT_DIR}/artifacts/status-api-linux.tar.gz" .

echo "Artefato gerado em artifacts/status-api-linux.tar.gz"
