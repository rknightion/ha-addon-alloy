#!/usr/bin/env bash
# Test harness for generate-config.sh
# Usage: tests/generate-config.test.sh
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="${REPO_ROOT}/alloy/rootfs/usr/share/alloy/generate-config.sh"
ALLOY_IMAGE="grafana/alloy:v1.17.0"
FAILS=0
TESTS=0

fail() { echo "  ✗ $1"; FAILS=$((FAILS+1)); }
pass() { echo "  ✓ $1"; }
check_contains() { TESTS=$((TESTS+1)); if grep -qF -- "$2" <<<"$1"; then pass "contains: $2"; else fail "MISSING: $2"; fi; }
check_absent()   { TESTS=$((TESTS+1)); if grep -qF -- "$2" <<<"$1"; then fail "SHOULD BE ABSENT: $2"; else pass "absent: $2"; fi; }

# Run the generator. Each call site wraps the invocation in its own subshell with
# explicit `export`s, so option vars reach the script and don't leak between cases.
gen() { bash "$GEN"; }

# Validate Alloy config syntax+semantics via Docker, if available.
validate_alloy() {
  local cfg="$1" name="$2"
  if ! command -v docker >/dev/null 2>&1; then echo "  ⚠ docker absent — skipping Alloy validation for $name"; return 0; fi
  local tmp; tmp="$(mktemp -d)"; printf '%s\n' "$cfg" > "$tmp/config.alloy"
  TESTS=$((TESTS+1))
  # `alloy fmt` parses River grammar; non-zero on syntax error.
  if docker run --rm -v "$tmp:/c:ro" "$ALLOY_IMAGE" fmt /c/config.alloy >/dev/null 2>"$tmp/err"; then
    pass "alloy fmt OK ($name)"
  else
    fail "alloy fmt FAILED ($name): $(cat "$tmp/err")"
  fi
  # `alloy run` for ~4s catches semantic errors (unknown component/arg/function).
  # Expect it NOT to print a config load error; the timeout itself is success.
  TESTS=$((TESTS+1))
  local out
  out="$(docker run --rm -v "$tmp:/c:ro" "$ALLOY_IMAGE" run --server.http.listen-addr=0.0.0.0:0 --storage.path=/tmp/d /c/config.alloy 2>&1 & p=$!; sleep 4; kill $p 2>/dev/null; wait $p 2>/dev/null)"
  if grep -qiE 'error during the initial|could not perform|failed to (build|load)|unrecognized|parse error|expected .* but got|invalid (argument|expression)' <<<"$out"; then
    fail "alloy run reported config error ($name): $(grep -iE 'error|expected|invalid' <<<"$out" | head -3)"
  else
    pass "alloy run loaded config ($name)"
  fi
  rm -rf "$tmp"
}

echo "== logs-only =="
OUT="$(export LOG_LEVEL=info JOURNAL_PATH=/var/log/journal LOKI_URL=http://loki:3100/loki/api/v1/push; gen)"
check_contains "$OUT" 'logging {'
check_contains "$OUT" 'level = "info"'
check_contains "$OUT" 'loki.source.journal "journal"'
check_contains "$OUT" 'path         = "/var/log/journal"'
check_contains "$OUT" 'loki.write "loki"'
check_contains "$OUT" 'url = "http://loki:3100/loki/api/v1/push"'
check_absent   "$OUT" 'prometheus.exporter.unix'
validate_alloy "$OUT" "logs-only"

echo "== metrics-only (with basic auth) =="
OUT="$(export LOG_LEVEL=info PROMETHEUS_URL=http://prom:9090/api/v1/write PROMETHEUS_USERNAME=12345 INSTANCE_NAME=hass-test METRICS_SCRAPE_INTERVAL=30s; gen)"
check_contains "$OUT" 'prometheus.exporter.unix "host"'
check_contains "$OUT" 'discovery.relabel "host"'
check_contains "$OUT" 'target_label = "instance"'
check_contains "$OUT" 'replacement  = "hass-test"'
check_contains "$OUT" 'prometheus.scrape "host"'
check_contains "$OUT" 'targets         = discovery.relabel.host.output'
check_contains "$OUT" 'scrape_interval = "30s"'
check_contains "$OUT" 'prometheus.remote_write "metrics"'
check_contains "$OUT" 'url = "http://prom:9090/api/v1/write"'
check_contains "$OUT" 'basic_auth {'
check_contains "$OUT" 'username = "12345"'
check_contains "$OUT" 'password = sys.env("PROMETHEUS_PASSWORD")'
check_absent   "$OUT" 'loki.source.journal'
validate_alloy "$OUT" "metrics-only"

echo "== both, no auth =="
OUT="$(export LOG_LEVEL=warn JOURNAL_PATH=/run/log/journal LOKI_URL=http://loki:3100/loki/api/v1/push PROMETHEUS_URL=http://prom:9090/api/v1/write; gen)"
check_contains "$OUT" 'loki.source.journal "journal"'
check_contains "$OUT" 'prometheus.exporter.unix "host"'
check_contains "$OUT" 'prometheus.remote_write "metrics"'
check_contains "$OUT" 'replacement  = "homeassistant"'
check_contains "$OUT" 'scrape_interval = "60s"'
check_absent   "$OUT" 'basic_auth {'
validate_alloy "$OUT" "both-noauth"

echo ""
echo "== RESULTS: $((TESTS-FAILS))/$TESTS checks passed =="
[ "$FAILS" -eq 0 ] || { echo "FAILED ($FAILS)"; exit 1; }
echo "ALL PASS"
