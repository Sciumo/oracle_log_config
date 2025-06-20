#!/usr/bin/env bash

# ============================================================================
# get_oracle_logging_config.sh – Comprehensive Oracle logging audit for Linux/Unix
# ----------------------------------------------------------------------------
# This script generates a detailed report of the current Oracle logging,
# auditing, and tracing configuration. It is designed to be the Bash
# equivalent of the Get-OracleLoggingConfig.ps1 script.
#
# Usage example:
#   ./get_oracle_logging_config.sh -s oradb01 -d ORCL -u system
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ---------- defaults --------------------------------------------------------
PORT=1521
OUTPUT_DIR="./logs"
SQLPLUS_PATH="sqlplus"

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
  -o | --output      <directory>             (default ./logs)
  -x | --sqlplus     <path to sqlplus>       (default sqlplus)
  -h | --help
EOF
  exit 1
}

# ---------- arg parse -------------------------------------------------------
ARGS=$(getopt -o s:d:u:p:P:o:x:h --long server:,service:,username:,password:,port:,output:,sqlplus:,help -n "$0" -- "$@") || usage

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
    -h|--help)      usage;;
    --) shift; break;;
    *) usage;;
  esac
done

# ---------- sanity ----------------------------------------------------------
[ -z "${SERVER:-}"   ] && error "server is required" && usage
[ -z "${SERVICE:-}"  ] && error "service is required" && usage
[ -z "${USERNAME:-}" ] && error "username is required" && usage

command -v "$SQLPLUS_PATH" >/dev/null 2>&1 || { error "sqlplus not found: $SQLPLUS_PATH"; exit 2; }

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SQL_FILE="${OUTPUT_DIR}/oracle_logging_audit_${TIMESTAMP}.sql"
OUTPUT_FILE="${OUTPUT_DIR}/oracle_logging_config_${TIMESTAMP}.txt"
LOG_FILE="${OUTPUT_DIR}/oracle_audit_${TIMESTAMP}.log"

log "Oracle Logging Configuration Documentation Script"
log "=================================================="

# Get password if not provided
if [ -z "${PASSWORD:-}" ]; then
  read -srp "Enter password for $USERNAME: " PASSWORD; echo
fi

log "Configuration:"
echo "  Server: $SERVER"
echo "  Port: $PORT"
echo "  Service: $SERVICE"
echo "  Username: $USERNAME"
echo "  Output Directory: $OUTPUT_DIR"
echo "  SQL File: $SQL_FILE"
echo "  Output File: $OUTPUT_FILE"

# --- Create the SQL script content ---
# This SQL payload is identical to the PowerShell version to ensure consistent reports.
cat > "$SQL_FILE" <<EOF
-- Oracle Logging, Audit, and Trace Configuration Documentation
-- Generated on: $TIMESTAMP
-- Database: ${SERVER}:${PORT}/${SERVICE}

SET PAGESIZE 1000
SET LINESIZE 200
SET TRIMSPOOL ON
SET ECHO OFF
SET FEEDBACK OFF
SET HEADING ON

SPOOL $OUTPUT_FILE

PROMPT ===============================================
PROMPT ORACLE DATABASE LOGGING CONFIGURATION REPORT
PROMPT ===============================================
PROMPT
PROMPT Database Information:
COLUMN instance_name FORMAT A20
COLUMN host_name FORMAT A30
COLUMN version FORMAT A20
SELECT instance_name, host_name, version, startup_time, database_status 
FROM v\$instance;

PROMPT
PROMPT Database Name and ID:
COLUMN db_name FORMAT A20
COLUMN log_mode FORMAT A15
COLUMN open_mode FORMAT A15
SELECT name as db_name, dbid, log_mode, open_mode 
FROM v\$database;

PROMPT
PROMPT ===============================================
PROMPT AUDIT CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Current Audit Parameters:
COLUMN name FORMAT A40
COLUMN value FORMAT A60
SELECT name, value 
FROM v\$parameter 
WHERE name LIKE '%audit%' 
ORDER BY name;

PROMPT
PROMPT Statement Audit Options (What statements are being audited):
COLUMN user_name FORMAT A30
COLUMN audit_option FORMAT A40
SELECT user_name, audit_option, success, failure 
FROM dba_stmt_audit_opts 
ORDER BY user_name, audit_option;

PROMPT
PROMPT Privilege Audit Options:
COLUMN privilege FORMAT A40
SELECT user_name, privilege, success, failure 
FROM dba_priv_audit_opts 
ORDER BY user_name, privilege;

PROMPT
PROMPT Object Audit Options:
COLUMN owner FORMAT A20
COLUMN object_name FORMAT A30
COLUMN object_type FORMAT A20
SELECT owner, object_name, object_type, alt, aud, com, del, gra, ind, ins, loc, ren, sel, upd, ref, exe, cre, rea, wri, fbk
FROM dba_obj_audit_opts 
WHERE alt != '-/-' OR aud != '-/-' OR com != '-/-' OR del != '-/-' 
   OR gra != '-/-' OR ind != '-/-' OR ins != '-/-' OR loc != '-/-'
   OR ren != '-/-' OR sel != '-/-' OR upd != '-/-' OR ref != '-/-'
   OR exe != '-/-' OR cre != '-/-' OR rea != '-/-' OR wri != '-/-' OR fbk != '-/-'
ORDER BY owner, object_name;

PROMPT
PROMPT Unified Auditing Policies (12c+):
COLUMN policy_name FORMAT A30
COLUMN enabled_option FORMAT A15
COLUMN entity_name FORMAT A30
COLUMN entity_type FORMAT A15
SELECT policy_name, enabled_option, entity_name, entity_type, success, failure
FROM audit_unified_enabled_policies
ORDER BY policy_name, entity_name;

PROMPT
PROMPT ===============================================
PROMPT SQL TRACING CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT SQL Trace and Timing Parameters:
SELECT name, value
FROM v\$parameter 
WHERE name IN ('sql_trace', 'timed_statistics', 'max_dump_file_size', 
               'user_dump_dest', 'background_dump_dest', 'diagnostic_dest',
               'sql_trace_waits', 'sql_trace_binds')
ORDER BY name;

PROMPT
PROMPT Event Parameters (10046, 10053, etc.):
SELECT name, value 
FROM v\$parameter 
WHERE name LIKE '%event%' AND value IS NOT NULL;

PROMPT
PROMPT Current Session Trace Settings:
COLUMN username FORMAT A30
COLUMN program FORMAT A40
COLUMN machine FORMAT A40
SELECT s.sid, s.serial#, s.username, s.sql_trace, s.sql_trace_waits, s.sql_trace_binds,
       s.program, s.machine
FROM v\$session s 
WHERE s.username IS NOT NULL
ORDER BY s.username, s.sid;

PROMPT
PROMPT ===============================================
PROMPT ALERT LOG AND DIAGNOSTIC CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Alert Log and Diagnostic Parameters:
SELECT name, value 
FROM v\$parameter 
WHERE name LIKE '%log%' AND name LIKE '%alert%'
   OR name LIKE '%diagnostic%'
   OR name LIKE '%dump%'
   OR name IN ('log_checkpoints_to_alert', 'log_archive_trace')
ORDER BY name;

PROMPT
PROMPT ADR (Automatic Diagnostic Repository) Information:
COLUMN adr_home FORMAT A80
COLUMN adr_base FORMAT A80
SELECT inst_id, comp_id, adr_home, adr_base
FROM v\$diag_info;

PROMPT
PROMPT ===============================================
PROMPT ARCHIVE LOG AND REDO LOG CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Archive Log Parameters:
SELECT name, value 
FROM v\$parameter 
WHERE name LIKE '%archive%' OR name LIKE '%log_archive%'
ORDER BY name;

PROMPT
PROMPT Archive Log Destinations:
COLUMN destination FORMAT A60
SELECT dest_id, status, destination, target, schedule
FROM v\$archive_dest 
WHERE status != 'INACTIVE';

PROMPT
PROMPT Redo Log Groups and Sizes:
SELECT l.group#, l.thread#, l.sequence#, l.bytes/1024/1024 as size_mb, 
       l.blocksize, l.members, l.status
FROM v\$log l
ORDER BY l.group#;

PROMPT
PROMPT ===============================================
PROMPT SPACE USAGE AND GROWTH RATE ANALYSIS
PROMPT ===============================================

PROMPT
PROMPT Archive Log Space Usage (FRA):
COLUMN name FORMAT A60
SELECT name,
       space_limit/1024/1024/1024 as limit_gb, 
       space_used/1024/1024/1024 as used_gb,
       round(space_used/space_limit*100,2) as pct_used
FROM v\$recovery_file_dest;

PROMPT
PROMPT Archive Log Generation Per Day (Last 7 Days):
COLUMN day FORMAT A15
COLUMN generated_gb FORMAT 999,999.99
SELECT to_char(trunc(completion_time), 'YYYY-MM-DD') AS day,
       round(sum(blocks * block_size) / 1024 / 1024 / 1024, 2) AS generated_gb,
       count(*) as file_count
FROM v\$archived_log
WHERE completion_time > SYSDATE - 7
GROUP BY trunc(completion_time)
ORDER BY day;

PROMPT
PROMPT Redo Log Switches Per Hour (Last 24 Hours):
COLUMN hour FORMAT A15
SELECT to_char(first_time, 'YYYY-MM-DD HH24') || ':00' AS hour,
       count(*) AS switches
FROM v\$log_history
WHERE first_time > SYSDATE - 1
GROUP BY to_char(first_time, 'YYYY-MM-DD HH24')
ORDER BY hour;

PROMPT
PROMPT Large Diagnostic Files (>10MB) - Includes Trace and Audit XML Files:
COLUMN trace_filename FORMAT A100
SELECT trace_filename,
       sizeblks*block_size/1024/1024 as size_mb,
       to_char(change_time, 'YYYY-MM-DD HH24:MI:SS') as last_modified
FROM v\$diag_trace_file 
WHERE sizeblks*block_size > 10*1024*1024
ORDER BY sizeblks DESC;

PROMPT
PROMPT Report completed at: 
SELECT to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS') as report_time FROM dual;

SPOOL OFF
SET FEEDBACK ON
SET ECHO ON
EXIT;
EOF

log "SQL script created: $SQL_FILE"

# --- Construct connection string ---
CONNECT_STR="${USERNAME}/${PASSWORD}@${SERVER}:${PORT}/${SERVICE}"
# Check for SYS user and append 'as sysdba' if needed
if [[ "${USERNAME,,}" == "sys" ]]; then
  CONNECT_STR="${CONNECT_STR} as sysdba"
  log "Connecting as SYSDBA."
else
  warn "Note: For a complete report, running as SYS or a user with SYSDBA privileges is recommended."
fi

log "\nExecuting Oracle audit script..."
echo "Start time: $(date)"

# --- Execute SQL*Plus ---
# Redirect both stdout and stderr to the log file
if "$SQLPLUS_PATH" -s "$CONNECT_STR" @"$SQL_FILE" > "$LOG_FILE" 2>&1; then
    log "\nScript executed successfully!"
    echo "Output file: $OUTPUT_FILE"
    echo "Log file: $LOG_FILE"
    
    # Show file sizes
    if [ -f "$OUTPUT_FILE" ]; then
        SIZE_KB=$(du -k "$OUTPUT_FILE" | cut -f1)
        echo "Output file size: ${SIZE_KB} KB"
    fi
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE_KB=$(du -k "$LOG_FILE" | cut -f1)
        echo "Log file size: ${LOG_SIZE_KB} KB"
    fi
else
    SQL_EXIT_CODE=$?
    error "ERROR: SQL*Plus exited with code $SQL_EXIT_CODE"
    if [ -f "$LOG_FILE" ]; then
        warn "Check log file for details: $LOG_FILE"
        echo -e "\nLast few lines of log:"
        tail -n 10 "$LOG_FILE"
    fi
    # Clean up the temp SQL file on failure too
    rm -f "$SQL_FILE"
    exit $SQL_EXIT_CODE
fi

echo -e "\nEnd time: $(date)"

# --- Cleanup ---
rm -f "$SQL_FILE"

log "\nOracle logging configuration audit completed!"
if [ -f "$OUTPUT_FILE" ]; then
    warn "To view the report: cat '$OUTPUT_FILE' | less"
fi