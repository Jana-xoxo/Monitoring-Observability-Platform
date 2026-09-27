#!/bin/bash
# Bring the Project 13 stack up. Owned by Rana.
#
#   bash scripts/start-services.sh             the normal four services
#   bash scripts/start-services.sh <profile>   also start services in that Compose profile
#
set -euo pipefail

cd "$(dirname "$0")/../stack"

LOG_FILE="$HOME/project13-logs/start-services.log"
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

if ! docker compose version >/dev/null 2>&1; then
    log "[ERROR] Docker Compose plugin not found. This script only runs on the VM, not in Cloud Shell."
    exit 1
fi

if [ ! -f .env ]; then
    log "[ERROR] stack/.env is missing. Run scripts/setup-env.sh, then put the real Grafana password in it."
    exit 1
fi

if grep -q "change_this_secure_password" .env; then
    log "[WARN] stack/.env still has the placeholder Grafana password. Anyone who can reach port 3000 can guess it."
fi

PROFILE="${1:-}"
if [ -n "$PROFILE" ]; then
    log "[INFO] Starting stack with profile: $PROFILE"
    COMPOSE_PROFILES="$PROFILE" docker compose up -d
else
    log "[INFO] Starting stack"
    docker compose up -d
fi

log "[INFO] Waiting for containers to settle"
sleep 10

docker compose ps --format '{{.Service}}	{{.Status}}' | tee -a "$LOG_FILE"

log "[INFO] Started. Run scripts/health-check.sh to confirm it is actually working."
