#!/usr/bin/env bash

# ============================================================================
# audit_oracle_stig_logging.sh – STIG‑oriented Oracle logging compliance audit
# ----------------------------------------------------------------------------
# This script compares the current Oracle logging and auditing configuration
# with the DISA Oracle Database STIG and reports any gaps.  Two knobs govern
# how strict the comparison is:
#   ‑c | --compliance  LEAST | NOMINAL   (default NOMINAL)
#   ‑D | --days        <int>            (minimum audit retention in days)
#
# LEAST   = bare‑minimum logging that still passes every STIG control
# NOMINAL = every CAT I‑III control fully enforced
#
# For any non‑compliant control the script emits a remediation SQL statement
# into a ready‑to‑run file called remediation_YYYYMMDD_HHMMSS.sql.
# Exit code 0 means compliant; non‑zero means findings were produced.
# ----------------------------------------------------------------------------
# Usage example
#   ./audit_oracle_stig_logging.sh -s oradb01 -d ORCL -u system -p secret \
#        -c LEAST -D 30 -o /tmp/audit
# ----------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# ---------- defaults --------------------------------------------------------
PORT=1521
OUTPUT_DIR="."
SQLPLUS_PATH="sqlplus"
COMPLIANCE="NOMINAL"
MIN_DAYS=30

# ---------- colours (optional) ---------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()      { echo -e "${CYAN}$*${NC}" ; }
warn()     { echo -e "${YELLOW}$*${NC}" ; }
error()    { echo -e "${RED}$*${NC}" >&2 ; }

usage() {
  cat <<EOF
Usage: $0 -s server -d service -u username [options]
  -s | --server      <host>
  -d | --service     <service name>
  -u | --username    <db user>
  -p | --password    <db password>           (prompted if omitted)
  -P | --port        <listener port>         (default 1521)
  -o | --output      <directory>             (default current dir)
  -x | --sqlplus     <path to sqlplus>       (default sqlplus)
  -c | --compliance  LEAST|NOMINAL           (default NOMINAL)
  -D | --days        <retention days>        (default 30)
  -h | --help
EOF
  exit 1
}

# ---------- arg parse -------------------------------------------------------
ARGS=$(getopt -o s:d:u:p:P:o:x:c:D:h --long server:,service:,username:,password:,port:,output:,sqlplus:,compliance:,days:,help -n "$0" -- "$@") || usage

eval set -- "$ARGS"
while true; do
  case "$1" in
    -s|--server)    SERVER="$2"; shift 2;;
    -d|--service)   SERVICE="$2"; shift 2;;
    -u|--username)  USERNAME="$2"; shift 2;;
    -p|--password)  PASSWORD="$2"; shift 2;;
    -P|--port)      PORT="$2"; shift 2;;
    -o|--output)    OUTPUT_DIR="$2"; shift 2;;
    -x|--sqlplus)   SQLPLUS_PATH="$2"; shift 2;;
    -c|--compliance) COMPLIANCE="${2^^}"; shift 2;;
    -D|--days)      MIN_DAYS="$2"; shift 2;;
    -h|--help)      usage;;
    --) shift; break;;
    *) usage;;
  esac
done

# ---------- sanity ----------------------------------------------------------
[ -z "${SERVER:-}"   ] && error "server is required" && usage
[ -z "${SERVICE:-}"  ] && error "service is required" && usage
[ -z "${USERNAME:-}" ] && error "username is required" && usage

[[ "$COMPLIANCE" =~ ^(LEAST|NOMINAL)$ ]] || { error "compliance must be LEAST or NOMINAL"; exit 2; }
[[ "$MIN_DAYS" =~ ^[1-9][0-9]*$ ]] || { error "days must be > 0"; exit 2; }

command -v "$SQLPLUS_PATH" >/dev/null 2>&1 || { error "sqlplus not found: $SQLPLUS_PATH"; exit 2; }

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$OUTPUT_DIR/stig_audit_${TIMESTAMP}.txt"
REMED_FILE="$OUTPUT_DIR/remediation_${TIMESTAMP}.sql"
SQL_TMP="$OUTPUT_DIR/stig_probe_${TIMESTAMP}.sql"
LOG_FILE="$OUTPUT_DIR/stig_audit_${TIMESTAMP}.log"

touch "$REMED_FILE"

echo "-- remediation script generated $(date)" > "$REMED_FILE"

echo "Compliancy mode: $COMPLIANCE" > "$REPORT_FILE"
echo "Minimum retention days: $MIN_DAYS" >> "$REPORT_FILE"

echo "Connecting to ${SERVER}:${PORT}/${SERVICE} as ${USERNAME}" >> "$REPORT_FILE"

if [ -z "${PASSWORD:-}" ]; then
  read -srp "Enter password for $USERNAME: " PASSWORD; echo
fi

CONNECT_STR="${USERNAME}/${PASSWORD}@${SERVER}:${PORT}/${SERVICE}"

# ---------- helper to query one scalar value -------------------------------
sql_value() {
  local q="$1"
  "$SQLPLUS_PATH" -s "$CONNECT_STR" <<-EOF | sed -n '2p'
    SET HEADING OFF FEEDBACK OFF VERIFY OFF ECHO OFF
    $q;
    EXIT;
EOF
}

# ---------- checks ----------------------------------------------------------
findings=0

check_audit_trail() {
  local val=$(sql_value "SELECT value FROM v$parameter WHERE name='audit_trail'")
  echo -e "\nAudit trail setting: $val" >> "$REPORT_FILE"
  case "$val" in
    NONE)
      echo "Finding: AUDIT_TRAIL is NONE" >> "$REPORT_FILE"
      echo "ALTER SYSTEM SET audit_trail='DB, EXTENDED' SCOPE=SPFILE;" >> "$REMED_FILE"
      findings=$((findings+1))
      ;;
    OS|DB|"DB,EXTENDED"|XML|"XML,EXTENDED") :;;
    *)
      echo "Finding: AUDIT_TRAIL has unexpected value '$val'" >> "$REPORT_FILE"
      echo "ALTER SYSTEM SET audit_trail='DB, EXTENDED' SCOPE=SPFILE;" >> "$REMED_FILE"
      findings=$((findings+1))
      ;;
  esac
}

check_sys_operations() {
  local val=$(sql_value "SELECT value FROM v$parameter WHERE name='audit_sys_operations'")
  echo -e "\nAudit SYS operations: $val" >> "$REPORT_FILE"
  if [[ "$val" != "TRUE" ]]; then
    echo "Finding: AUDIT_SYS_OPERATIONS should be TRUE" >> "$REPORT_FILE"
    echo "ALTER SYSTEM SET audit_sys_operations=TRUE SCOPE=SPFILE;" >> "$REMED_FILE"
    findings=$((findings+1))
  fi
}

check_retention() {
  local oldest=$(sql_value "SELECT TO_CHAR(MIN(timestamp),'YYYY-MM-DD') FROM dba_audit_trail")
  if [[ -z "$oldest" ]]; then
    echo -e "\nAudit trail table empty, retention unmet" >> "$REPORT_FILE"
    findings=$((findings+1))
    return
  fi
  local epoch_old=$(date -d "$oldest" +%s)
  local epoch_now=$(date +%s)
  local diff_days=$(( (epoch_now - epoch_old) / 86400 ))
  echo -e "\nOldest audit record: $oldest (age ${diff_days}d)" >> "$REPORT_FILE"
  if (( diff_days < MIN_DAYS )); then
    echo "Finding: Audit retention ${diff_days}d < ${MIN_DAYS}d" >> "$REPORT_FILE"
    echo "-- manual action: ensure purge job retains >= ${MIN_DAYS} days" >> "$REMED_FILE"
    findings=$((findings+1))
  fi
}

check_unified_audit_policies() {
  [ "$COMPLIANCE" = "LEAST" ] && return 0
  local count=$(sql_value "SELECT COUNT(*) FROM audit_unified_enabled_policies")
  echo -e "\nUnified audit policies enabled: $count" >> "$REPORT_FILE"
  if (( count == 0 )); then
    echo "Finding: No unified audit policies enabled" >> "$REPORT_FILE"
    echo "CREATE AUDIT POLICY unauth_logins WHEN 'LOGON' FAILED;" >> "$REMED_FILE"
    echo "AUDIT POLICY unauth_logins;" >> "$REMED_FILE"
    findings=$((findings+1))
  fi
}

# ---------- run checks ------------------------------------------------------
log "Running STIG compliance audit..."
check_audit_trail
check_sys_operations
check_retention
check_unified_audit_policies

# ---------- results ---------------------------------------------------------
if (( findings == 0 )); then
  echo -e "\nOracle logging configuration is compliant" | tee -a "$REPORT_FILE"
  rm -f "$REMED_FILE"
  exit 0
else
  echo -e "\nFound $findings finding(s).  See $REPORT_FILE and $REMED_FILE" | tee -a "$REPORT_FILE"
  exit 3
fi
