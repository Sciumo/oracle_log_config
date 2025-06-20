#!/usr/bin/env bash

# ============================================================================
# apply_sql.sh – Apply STIG-compliant Oracle logging configuration
# ----------------------------------------------------------------------------
# This script applies the appropriate SQL hardening script. It can either
# map a compliance level to a file or run a specific file directly.
#
# Usage:
#   ./apply_sql.sh -s server -d service -u username -p password \
#                  -c LEAST|NOMINAL -D days
#   ./apply_sql.sh -s server -d service -u username -p password \
#                  -f /path/to/script.sql -D days
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ---------- defaults --------------------------------------------------------
PORT=1521
SQLPLUS_PATH="sqlplus"
COMPLIANCE="NOMINAL"
MIN_DAYS=30
SQL_FILE="" # variable for direct file path

# ---------- colours ---------------------------------------------------------
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
  -x | --sqlplus     <path to sqlplus>       (default sqlplus)
  -c | --compliance  LEAST|NOMINAL           (default NOMINAL)
  -f | --sql-file    <path to .sql file>     (overrides -c)
  -D | --days        <retention days>        (default 30)
  -h | --help
EOF
  exit 1
}

# ---------- arg parse -------------------------------------------------------
# Added -f and --sql-file to getopt
ARGS=$(getopt -o s:d:u:p:P:x:c:D:f:h --long server:,service:,username:,password:,port:,sqlplus:,compliance:,days:,sql-file:,help -n "$0" -- "$@") || usage

eval set -- "$ARGS"
while true; do
  case "$1" in
    -s|--server)    SERVER="$2"; shift 2;;
    -d|--service)   SERVICE="$2"; shift 2;;
    -u|--username)  USERNAME="$2"; shift 2;;
    -p|--password)  PASSWORD="$2"; shift 2;;
    -P|--port)      PORT="$2"; shift 2;;
    -x|--sqlplus)   SQLPLUS_PATH="$2"; shift 2;;
    -c|--compliance) COMPLIANCE="${2^^}"; shift 2;;
    -f|--sql-file)  SQL_FILE="$2"; shift 2;;
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

[[ "$COMPLIANCE" =~ ^(LEAST|NOMINAL|EXCESS)$ ]] || { error "compliance must be LEAST, NOMINAL, or EXCESS"; exit 2; }
[[ "$MIN_DAYS" =~ ^[1-9][0-9]*$ ]] || { error "days must be > 0"; exit 2; }

command -v "$SQLPLUS_PATH" >/dev/null 2>&1 || { error "sqlplus not found: $SQLPLUS_PATH"; exit 2; }

# Determine script directory
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# UPDATED LOGIC: Prioritize direct file path over compliance mapping
if [ -n "$SQL_FILE" ]; then
  SQL_PATH="$SQL_FILE"
  log "Applying specified SQL file: $SQL_PATH"
else
  # Map compliance level to SQL file
  case "$COMPLIANCE" in
    LEAST)   SQL_FILE="least_hardening.sql" ;;
    NOMINAL) SQL_FILE="hardening.sql" ;;
  esac
  log "Applying $COMPLIANCE compliance using $SQL_FILE"

  # Check if we're running in a container (common container paths)
  if [[ "$SCRIPT_DIR" == "/tmp" ]] || [[ -f "/tmp/${SQL_FILE}" ]]; then
    # Running inside container, SQL files should be in /tmp
    SQL_PATH="/tmp/${SQL_FILE}"
  else
    # Running on host
    SQL_PATH="${SCRIPT_DIR}/${SQL_FILE}"
  fi
fi

if [ ! -f "$SQL_PATH" ]; then
  error "SQL file not found: $SQL_PATH"
  exit 2
fi

log "Retention days: $MIN_DAYS"
log "Connecting to ${SERVER}:${PORT}/${SERVICE} as ${USERNAME}"

if [ -z "${PASSWORD:-}" ]; then
  read -srp "Enter password for $USERNAME: " PASSWORD; echo
fi

if [[ "${USERNAME,,}" == "sys" ]]; then
  CONNECT_STR="${USERNAME}/${PASSWORD}@${SERVER}:${PORT}/${SERVICE} as sysdba"
else
  CONNECT_STR="${USERNAME}/${PASSWORD}@${SERVER}:${PORT}/${SERVICE}"
fi

# Execute SQL directly with parameter
log "Executing SQL script..."
"$SQLPLUS_PATH" -s "$CONNECT_STR" "@$SQL_PATH" "$MIN_DAYS"

SQL_EXIT=$?

if [ $SQL_EXIT -eq 0 ]; then
  log "SQL script completed successfully"
  log "Note: Database restart may be required to activate SPFILE parameter changes"
  exit 0
else
  error "SQL script failed with exit code $SQL_EXIT"
  exit $SQL_EXIT
fi