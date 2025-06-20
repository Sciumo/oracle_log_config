#!/usr/bin/env bash
# ============================================================================
# audit_oracle_stig_logging.sh – Oracle logging compliance audit
# ----------------------------------------------------------------------------
#   Verifies a database against DISA Oracle Database STIG controls
#   relevant to logging & auditing. Generates a human-readable report
#   and an auto-remediation SQL file.
#
#   Key STIG controls referenced below (19c, Rev. 4):
#     V-215627  audit_trail NONE for Pure Unified Auditing
#     V-215621  AUDIT_SYS_OPERATIONS TRUE for CAT I events
#     V-215648  Retain audit trail ≥ 365 days (one year)
#     V-215650  Failed-login events must be audited
#     V-215646  DBA privilege actions must be audited (NOMINAL)
# ----------------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# ---------- defaults --------------------------------------------------------
PORT=1521
OUTPUT_DIR="./logs"
SQLPLUS_PATH="sqlplus"
COMPLIANCE="NOMINAL"    # LEAST | NOMINAL
MIN_DAYS=30

# ---------- colours ---------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()   { echo -e "${CYAN}$*${NC}"; }
warn()  { echo -e "${YELLOW}$*${NC}"; }
error() { echo -e "${RED}$*${NC}" >&2; }

usage() {
  cat <<EOF
Usage: $0 -s server -d service -u username [options]
  -s | --server      <host>
  -d | --service     <service name>
  -u | --username    <db user>
  -p | --password    <db password>     (prompted if omitted)
  -P | --port        <listener port>   (default 1521)
  -o | --output      <directory>       (default ./logs)
  -x | --sqlplus     <path to sqlplus> (default sqlplus)
  -c | --compliance  LEAST|NOMINAL     (default NOMINAL)
  -D | --days        <retention days>  (default 30)
  -h | --help
EOF
  exit 1
}

# ---------- arg parse -------------------------------------------------------
ARGS=$(getopt -o s:d:u:p:P:o:x:c:D:h \
      --long server:,service:,username:,password:,port:,output:,sqlplus:,compliance:,days:,help \
      -n "$0" -- "$@") || usage
eval set -- "$ARGS"
while true; do
  case "$1" in
    -s|--server)    SERVER="$2"; shift 2 ;;
    -d|--service)   SERVICE="$2"; shift 2 ;;
    -u|--username)  USERNAME="$2"; shift 2 ;;
    -p|--password)  PASSWORD="$2"; shift 2 ;;
    -P|--port)      PORT="$2"; shift 2 ;;
    -o|--output)    OUTPUT_DIR="$2"; shift 2 ;;
    -x|--sqlplus)   SQLPLUS_PATH="$2"; shift 2 ;;
    -c|--compliance) COMPLIANCE="${2^^}"; shift 2 ;;
    -D|--days)      MIN_DAYS="$2"; shift 2 ;;
    -h|--help)      usage ;;
    --) shift; break ;;
    *) usage ;;
  esac
done

# ---------- sanity ----------------------------------------------------------
[ -z "${SERVER:-}"   ] && error "server is required" && usage
[ -z "${SERVICE:-}"  ] && error "service is required" && usage
[ -z "${USERNAME:-}" ] && error "username is required" && usage
[[ "$COMPLIANCE" =~ ^(LEAST|NOMINAL)$ ]] || { error "compliance must be LEAST or NOMINAL"; exit 2; }
[[ "$MIN_DAYS" =~ ^[1-9][0-9]*$ ]] || { error "days must be > 0"; exit 2; }
command -v "$SQLPLUS_PATH" >/dev/null 2>&1 || { error "sqlplus not found: $SQLPLUS_PATH"; exit 2; }

# ---------- filenames -------------------------------------------------------
mkdir -p "$OUTPUT_DIR"
TS=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$OUTPUT_DIR/stig_audit_${TS}.txt"
REMED_FILE="$OUTPUT_DIR/remediation_${TS}.sql"

echo "-- remediation script generated $(date)" > "$REMED_FILE"
echo "-- NOTE: Some actions require a database restart and are marked so." >> "$REMED_FILE"

echo "Compliancy mode: $COMPLIANCE"       >  "$REPORT_FILE"
echo "Minimum retention days: $MIN_DAYS"  >> "$REPORT_FILE"
echo "Connecting to ${SERVER}:${PORT}/${SERVICE} as ${USERNAME}" >> "$REPORT_FILE"

# ---------- connect string --------------------------------------------------
if [ -z "${PASSWORD:-}" ]; then read -srp "Enter password for $USERNAME: " PASSWORD; echo; fi
if [[ "${USERNAME,,}" == "sys" ]]; then
  CONNECT_STR="${USERNAME}/${PASSWORD}@${SERVER}:${PORT}/${SERVICE} as sysdba"
else
  CONNECT_STR="${USERNAME}/${PASSWORD}@${SERVER}:${PORT}/${SERVICE}"
fi

# ---------- helper to pull a single scalar ----------------------------------
# SQL*Plus prints the value on the first output line when HEADING OFF is set,
# so capture that line with `head -n 1`.
sql_value() {
  local q="$1"
  "$SQLPLUS_PATH" -s "$CONNECT_STR" <<-EOF | head -n 1 | xargs
    SET HEADING OFF FEEDBACK OFF VERIFY OFF ECHO OFF PAGESIZE 0 TRIMSPOOL ON
    $q;
    EXIT;
EOF
}

# ---------- checks ----------------------------------------------------------
findings=0

# --- V-215627 : traditional auditing must be OFF for pure unified -----------
check_audit_trail() {
  local val
  val=$(sql_value "SELECT value FROM v\$parameter WHERE name='audit_trail'")
  echo -e "\nCHECK (V-215627): AUDIT_TRAIL = NONE for Pure Unified Auditing" >> "$REPORT_FILE"
  echo "  - Found: $val" >> "$REPORT_FILE"
  if [[ "$val" != "NONE" ]]; then
    echo "  - Finding: AUDIT_TRAIL must be NONE (found '$val')." >> "$REPORT_FILE"
    echo "-- Remediation (REQUIRES RESTART): ALTER SYSTEM SET audit_trail=NONE SCOPE=SPFILE;" >> "$REMED_FILE"
    findings=$((findings+1))
  fi
}

# --- V-215621 : audit_sys_operations TRUE (NOMINAL only) --------------------
check_sys_operations() {
  [ "$COMPLIANCE" = "LEAST" ] && return 0
  local val
  val=$(sql_value "SELECT value FROM v\$parameter WHERE name='audit_sys_operations'")
  echo -e "\nCHECK (V-215621): AUDIT_SYS_OPERATIONS TRUE (NOMINAL)" >> "$REPORT_FILE"
  echo "  - Found: $val" >> "$REPORT_FILE"
  if [[ "$val" != "TRUE" ]]; then
    echo "  - Finding: AUDIT_SYS_OPERATIONS should be TRUE." >> "$REPORT_FILE"
    echo "-- Remediation (REQUIRES RESTART): ALTER SYSTEM SET audit_sys_operations=TRUE SCOPE=SPFILE;" >> "$REMED_FILE"
    findings=$((findings+1))
  fi
}

# --- V-215648 : purge job present and retention >= MIN_DAYS -----------------
check_retention() {
  echo -e "\nCHECK (V-215648): Audit retention job exists & respects $MIN_DAYS days" >> "$REPORT_FILE"
  local job_count
  job_count=$(sql_value "SELECT COUNT(*) FROM dba_scheduler_jobs
                         WHERE job_name IN ('PURGE_UNIFIED_AUDIT_STIG','PURGE_AUDIT_TRAIL_STIG')")
  echo "  - Found $job_count accepted purge job(s)." >> "$REPORT_FILE"
  if (( job_count == 0 )); then
    echo "  - Finding: No STIG-compliant purge job configured." >> "$REPORT_FILE"
    echo "-- Remediation: run the appropriate *_post.sql hardening script." >> "$REMED_FILE"
    findings=$((findings+1))
  fi
}

# --- V-215650, V-215646 + baseline policy checks ----------------------------
check_unified_audit_policies() {
  echo -e "\nCHECK: Unified Audit Policy enablement" >> "$REPORT_FILE"

  # LEAST baseline
  local required=(STIG_LEAST_LOGON_POL STIG_LEAST_ADMIN_POL STIG_LEAST_SYS_ACTIONS_POL)

  # NOMINAL extras
  if [ "$COMPLIANCE" = "NOMINAL" ]; then
    required+=(STIG_NOM_SYS_PRIV_POL STIG_NOM_DML_POL)
  fi

  local legacy_alias=UA_FAILED_LOGINS_STIG
  local present_alias
  present_alias=$(sql_value "SELECT COUNT(*) FROM audit_unified_enabled_policies
                             WHERE policy_name='${legacy_alias}'")

  # Loop through rules
  for pol in "${required[@]}"; do
    local cnt
    cnt=$(sql_value "SELECT COUNT(*) FROM audit_unified_enabled_policies WHERE policy_name='${pol}'")
    echo "  - Policy '${pol}': $cnt enabled." >> "$REPORT_FILE"
    if (( cnt == 0 )); then
      echo "  - Finding: Required policy '${pol}' not enabled." >> "$REPORT_FILE"
      echo "-- Remediation: AUDIT POLICY ${pol};" >> "$REMED_FILE"
      findings=$((findings+1))
    fi
  done

  # Handle legacy failed-login alias
  if (( present_alias > 0 )); then
    echo "  - Legacy policy '${legacy_alias}' also enabled (covers failed logins)." >> "$REPORT_FILE"
  elif [[ "$(sql_value "SELECT COUNT(*) FROM audit_unified_enabled_policies
                        WHERE policy_name='STIG_LEAST_LOGON_POL'")" == "0" ]]; then
    # Neither new nor legacy policy audits LOGON
    echo "  - Finding: No LOGON policy enabled – failed logins not audited (V-215650)." >> "$REPORT_FILE"
    echo "-- Remediation: AUDIT POLICY STIG_LEAST_LOGON_POL;" >> "$REMED_FILE"
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
