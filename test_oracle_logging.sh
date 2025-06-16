#!/usr/bin/env bash
# ============================================================================
# test_audit_stig.sh  –  End‑to‑end acceptance test for audit_oracle_stig_logging
# ============================================================================
# This version pulls Oracle's official container image rather than building a
# bespoke Dockerfile.  It then walks an instance through the three compliance
# stages expected by the audit harness:       BASE → LEAST → NOMINAL → EXCESS.
# Any deviation causes the script to abort with a non‑zero exit status so it
# can run inside CI/CD.
# ----------------------------------------------------------------------------
# Expected project layout (project root = $PWD when this script runs):
#   audit_oracle_stig_logging.sh    – audit wrapper
#   least_hardening.sql             – minimal STIG baseline
#   hardening.sql                   – full STIG baseline
#   over_hardening.sql              – excessive logging baseline
#   test_audit_stig.sh              – this file
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 1. Globals and helpers
# ─────────────────────────────────────────────────────────────────────────────
ORACLE_IMAGE="${ORACLE_IMAGE:-oracle/database:19.3.0-ee}"
CONTAINER_NAME="oracle_stig_test$$"          # unique per run
ORACLE_PWD="${ORACLE_PWD:-Password123}"     # strong enough for test
DAYS_MIN=30                                   # retention threshold for LEAST & NOMINAL

log()   { printf "\e[32m▶ %s\e[0m\n" "$*"; }
err()   { printf "\e[31m✖ %s\e[0m\n" "$*" >&2; exit 1; }
wait_db_ready() {
  log "Waiting for database to open …"
  local h
  for h in {1..30}; do
    if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "DATABASE IS READY TO USE"; then
      log "Oracle reports READY after $h iterations"; return 0
    fi
    sleep 20
  done
  err "Database failed to become ready in allotted time"
}
run_sql() {
  local sql_file=$1
  docker exec "$CONTAINER_NAME" bash -lc "source /home/oracle/.bashrc && \
      sqlplus -s sys/$ORACLE_PWD@localhost:1521/ORCL as sysdba \@/scripts/$sql_file" || \
      err "SQL execution failed for $sql_file"
}
run_audit() {
  local days=$1 compliance=$2 outfile=$3
  docker exec "$CONTAINER_NAME" bash -lc "chmod +x /scripts/audit_oracle_stig_logging.sh && \
      /scripts/audit_oracle_stig_logging.sh \
        --server localhost --service ORCL --username sys --password $ORACLE_PWD \
        --days $days --compliance $compliance > /scripts/$outfile 2>&1" || true
}
expect_compliance() {
  local expected=$1 report=$2
  grep -q "^Compliance:[[:space:]]*$expected" "$report" || err "Expected $expected, saw $(grep '^Compliance:' "$report")"
  log "Compliance $expected verified in $report"
}

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ─────────────────────────────────────────────────────────────────────────────
# 2. Pull and launch base container
# ─────────────────────────────────────────────────────────────────────────────
log "Pulling Oracle image $ORACLE_IMAGE …"
docker pull "$ORACLE_IMAGE"

log "Starting test container $CONTAINER_NAME …"
docker run -d --name "$CONTAINER_NAME" -e ORACLE_PWD="$ORACLE_PWD" -p 1521:1521 \
  -v "$PWD":/scripts "$ORACLE_IMAGE" || err "Container failed to start"

wait_db_ready

# ─────────────────────────────────────────────────────────────────────────────
# 3. Stage 1 – Base image should fail audit (NOT‑COMPLIANT)
# ─────────────────────────────────────────────────────────────────────────────
log "Stage 1: auditing vanilla image (expect NOT‑COMPLIANT) …"
run_audit "$DAYS_MIN" "LEAST"            "stage1_base.txt"
expect_compliance "NOT-COMPLIANT" "stage1_base.txt"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Stage 2 – Apply least_hardening.sql and expect LEAST compliance
# ─────────────────────────────────────────────────────────────────────────────
log "Stage 2: applying least_hardening.sql …"
run_sql least_hardening.sql "$DAYS_MIN"
run_audit "$DAYS_MIN" "LEAST"            "stage2_least.txt"
expect_compliance "LEAST" "stage2_least.txt"

# ─────────────────────────────────────────────────────────────────────────────
# 5. Stage 3 – Apply hardening.sql and expect NOMINAL compliance
# ─────────────────────────────────────────────────────────────────────────────
log "Stage 3: applying hardening.sql …"
run_sql hardening.sql "$DAYS_MIN"
run_audit "$DAYS_MIN" "NOMINAL"          "stage3_nominal.txt"
expect_compliance "NOMINAL" "stage3_nominal.txt"

# ─────────────────────────────────────────────────────────────────────────────
# 6. Stage 4 – Apply over_hardening.sql and expect EXCESSIVE
# ─────────────────────────────────────────────────────────────────────────────
log "Stage 4: applying over_hardening.sql …"
run_sql over_hardening.sql 365
run_audit 365 "NOMINAL"                  "stage4_excess.txt"
expect_compliance "EXCESSIVE" "stage4_excess.txt"

log "All acceptance tests passed ✓"
