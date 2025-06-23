#!/usr/bin/env bash

# ============================================================================
# get_oracle_logging_config.sh – Comprehensive Oracle logging audit for Linux/Unix
# ----------------------------------------------------------------------------
# This script generates a detailed report of the current Oracle logging,
# GoldenGate, auditing, and tracing configuration. 
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
# Assume report.sql is in the same directory as this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SQL_SCRIPT_PATH="${SCRIPT_DIR}/report.sql"

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
[ -f "$SQL_SCRIPT_PATH" ] || { error "SQL script not found: $SQL_SCRIPT_PATH"; exit 3; }

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
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
echo "  SQL Script: $SQL_SCRIPT_PATH"
echo "  Output File: $OUTPUT_FILE"

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
# Call the external report.sql script, passing the output file path as an argument.
# Redirect both stdout and stderr to the log file.
if "$SQLPLUS_PATH" -s "$CONNECT_STR" @"$SQL_SCRIPT_PATH" "$OUTPUT_FILE" > "$LOG_FILE" 2>&1; then
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
    exit $SQL_EXIT_CODE
fi

echo -e "\nEnd time: $(date)"

# --- Cleanup ---
# No temporary files to clean up.

log "\nOracle logging configuration audit completed!"
if [ -f "$OUTPUT_FILE" ]; then
    warn "To view the report: cat '$OUTPUT_FILE' | less"
fi