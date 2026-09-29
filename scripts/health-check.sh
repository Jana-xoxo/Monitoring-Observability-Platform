#!/bin/bash
# Project 13 health check. Owned by Rana.
#
#   bash scripts/health-check.sh
#
# Exit 0 means everything is healthy. Exit 1 means at least one check failed,
# so this is safe to use in cron or a CI step.
#
# No -e on purpose. A failing curl must be recorded as a failed check,
# not kill the script before the remaining checks run.
set -uo pipefail

cd "$(dirname "$0")/../stack"

LOG_FILE="$HOME/project13-logs/health-check.log"
mkdir -p "$(dirname "$LOG_FILE")"

FAILED=0
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
pass() { log "  PASS  $1"; }
fail() { log "  FAIL  $1"; FAILED=$((FAILED + 1)); }

# Ports and credentials come from the same .env the stack uses,
# so this never drifts out of step with docker-compose.yml.
if [ -f .env ]; then
    set -a; . ./.env; set +a
fi
GF_USER="${GF_ADMIN_USER:-admin}"
GF_PASS="${GF_ADMIN_PASSWORD:-}"
PROM="http://localhost:${PROMETHEUS_PORT:-9090}"
GRAF="http://localhost:${GRAFANA_PORT:-3000}"

log "=== Project 13 health check ==="

# 1. Containers are running
for c in prometheus grafana node-exporter cadvisor; do
    status=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null | head -1 | tr -d '\r\n')
    [ -z "$status" ] && status="missing"
    if [ "$status" = "running" ]; then
        pass "container $c is running"
    else
        fail "container $c is $status"
    fi
done

# 2. Prometheus answers
if curl -sf --max-time 5 "$PROM/-/healthy" >/dev/null 2>&1; then
    pass "Prometheus is healthy on $PROM"
else
    fail "Prometheus did not answer on $PROM"
fi

# 3. Every scrape target is up
targets=$(curl -sf --max-time 5 "$PROM/api/v1/targets?state=active" 2>/dev/null)
if [ -z "$targets" ]; then
    fail "could not read Prometheus targets"
else
    down=$(printf '%s' "$targets" | python3 -c "
import sys, json
t = json.load(sys.stdin)['data']['activeTargets']
print(' '.join(x['labels']['job'] for x in t if x['health'] != 'up'))" 2>/dev/null)
    total=$(printf '%s' "$targets" | python3 -c "
import sys, json
print(len(json.load(sys.stdin)['data']['activeTargets']))" 2>/dev/null)
    if [ -z "$down" ]; then
        pass "all ${total:-?} scrape targets are up"
    else
        fail "scrape targets down: $down"
    fi
fi

# 4. Alert rules actually loaded
rules=$(curl -sf --max-time 5 "$PROM/api/v1/rules" 2>/dev/null | python3 -c "
import sys, json
g = json.load(sys.stdin)['data']['groups']
print(sum(len(x['rules']) for x in g))" 2>/dev/null)
if [ "${rules:-0}" -gt 0 ]; then
    pass "$rules alert rule(s) loaded"
else
    fail "no alert rules loaded, check stack/prometheus/rules/"
fi

# 5. Grafana answers
if curl -sf --max-time 5 "$GRAF/api/health" >/dev/null 2>&1; then
    pass "Grafana is healthy on $GRAF"
else
    fail "Grafana did not answer on $GRAF"
fi

# 6. The datasource exists and can reach Prometheus
if [ -z "$GF_PASS" ]; then
    log "  SKIP  datasource and dashboard checks, GF_ADMIN_PASSWORD not set in .env"
else
    ds=$(curl -sf --max-time 10 -u "$GF_USER:$GF_PASS" \
        "$GRAF/api/datasources/name/Prometheus" 2>/dev/null)
    if [ -z "$ds" ]; then
        fail "Grafana has no datasource named Prometheus"
    else
        uid=$(printf '%s' "$ds" | python3 -c "import sys,json;print(json.load(sys.stdin)['uid'])" 2>/dev/null)
        probe=$(curl -sf --max-time 10 -u "$GF_USER:$GF_PASS" \
            "$GRAF/api/datasources/uid/$uid/health" 2>/dev/null)
        if printf '%s' "$probe" | grep -q '"status":"OK"'; then
            pass "datasource Prometheus (uid $uid) can query Prometheus"
        else
            fail "datasource Prometheus (uid $uid) cannot query Prometheus"
        fi
    fi

    # 7. Dashboards provisioned
    n=$(curl -sf --max-time 10 -u "$GF_USER:$GF_PASS" \
        "$GRAF/api/search?type=dash-db" 2>/dev/null \
        | python3 -c "import sys,json;print(len(json.load(sys.stdin)))" 2>/dev/null)
    if [ "${n:-0}" -gt 0 ]; then
        pass "$n dashboard(s) provisioned"
    else
        fail "no dashboards provisioned, check stack/grafana/dashboards/"
    fi
fi

# 7. Metrics are on the persistent data disk, not the OS disk.
if [ -f /data/.NOT-PERSISTENT ]; then
    fail "/data is on the OS disk, metrics will be lost on the next rebuild"
elif findmnt -n /data >/dev/null 2>&1; then
    pass "/data mounted from $(findmnt -n -o SOURCE /data)"
else
    fail "/data is not a separate mount, metrics will be lost on the next rebuild"
fi

# Firing alerts are reported, not counted as a failure.
# The stack is healthy even when it is correctly telling you something is wrong.
firing=$(curl -sf --max-time 5 "$PROM/api/v1/alerts" 2>/dev/null | python3 -c "
import sys, json
a = json.load(sys.stdin)['data']['alerts']
print(', '.join(sorted({x['labels']['alertname'] for x in a if x['state'] == 'firing'})))" 2>/dev/null)
if [ -n "$firing" ]; then
    log "  NOTE  alerts currently firing: $firing"
fi

if [ "$FAILED" -eq 0 ]; then
    log "=== all checks passed ==="
else
    log "=== $FAILED check(s) FAILED ==="
fi
exit $(( FAILED > 0 ))
