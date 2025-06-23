#!/usr/bin/env bash

# ============================================================================
# run_report_on_docker.sh – Generate a logging report from the test container
# ----------------------------------------------------------------------------
# This utility script orchestrates the generation of a full logging and
# audit configuration report from the local test Docker container.
#
# It follows the project's standard pattern:
# 1. Copies the 'report.sql' script INTO the container.
# 2. Executes SQL*Plus INSIDE the container to generate the report.
# 3. Copies the resulting report file BACK OUT to the host's ./logs directory.
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Configuration (matches test_oracle_logging.sh) ---
CONTAINER_NAME="oracle_stig_test"
ORACLE_PWD="Oradoc_db1"
SQL_SCRIPT_NAME="report.sql" # The name of the SQL file on the host
OUTPUT_DIR="./logs"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${CYAN}$*${NC}" ; }
error() { echo -e "${RED}$*${NC}" >&2 ; }

# --- Sanity Checks ---
if ! command -v docker >/dev/null 2>&1; then
    error "Docker is not installed or not in the PATH. This script requires Docker."
    exit 1
fi
if [ ! -f "${SCRIPT_DIR}/${SQL_SCRIPT_NAME}" ]; then
    error "Core SQL script not found: '${SCRIPT_DIR}/${SQL_SCRIPT_NAME}'. Make sure it is in the same directory."
    exit 1
fi
if [ -z "$(docker ps -q -f name=^${CONTAINER_NAME}$)" ]; then
    error "The test container '${CONTAINER_NAME}' is not running. Please start it first (e.g., via test_oracle_logging.sh)."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Define file paths for clarity
HOST_SQL_PATH="${SCRIPT_DIR}/${SQL_SCRIPT_NAME}"
CONTAINER_SQL_PATH="/tmp/${SQL_SCRIPT_NAME}"
CONTAINER_OUTPUT_FILE="/tmp/docker_report_${TIMESTAMP}.txt"
HOST_OUTPUT_FILE="${OUTPUT_DIR}/docker_report_${TIMESTAMP}.txt"

log "Starting report generation for container: '${CONTAINER_NAME}'"

# --- 1. Copy the report script INTO the container ---
log "Step 1: Copying '${SQL_SCRIPT_NAME}' into the container at '${CONTAINER_SQL_PATH}'..."
if ! docker cp "${HOST_SQL_PATH}" "${CONTAINER_NAME}:${CONTAINER_SQL_PATH}"; then
    error "Failed to copy SQL script into the container."
    exit 1
fi
# Ensure oracle user can access it
docker exec -u root "${CONTAINER_NAME}" chown oracle:oinstall "${CONTAINER_SQL_PATH}"

# --- 2. Execute the report script INSIDE the container ---
log "Step 2: Executing SQL*Plus inside the container..."
# The -lc flag for bash is crucial to load the Oracle environment variables ($ORACLE_HOME/bin)
# The connection string uses 'localhost' because it's running from inside the container.
if ! docker exec -u oracle "${CONTAINER_NAME}" \
    bash -lc "sqlplus -s sys/\${ORACLE_PWD}@//localhost:1521/ORCLCDB as sysdba @${CONTAINER_SQL_PATH} ${CONTAINER_OUTPUT_FILE}"; then
    error "SQL*Plus execution failed inside the container. Check container logs for details: docker logs ${CONTAINER_NAME}"
    exit 1
fi
log "  -> SQL script executed successfully inside the container."

# --- 3. Copy the report file BACK OUT to the host ---
log "Step 3: Copying report file from container to host at '${HOST_OUTPUT_FILE}'..."
if ! docker cp "${CONTAINER_NAME}:${CONTAINER_OUTPUT_FILE}" "${HOST_OUTPUT_FILE}"; then
    error "Failed to copy report file from the container."
    exit 1
fi

log ""
log "Files in Oracle Trace > 1 MB  /opt/oracle/diag/rdbms/orclcdb/ORCLCDB/trace"
docker exec -u oracle "${CONTAINER_NAME}" bash -c "cd /opt/oracle/diag/rdbms/orclcdb/ORCLCDB/trace && find . -type f -size +1M -exec du -h {} \; | sort -rh"
log ""

# --- 4. Cleanup temporary files inside the container ---
log "Step 4: Cleaning up temporary files inside the container..."
docker exec "${CONTAINER_NAME}" rm "${CONTAINER_SQL_PATH}" "${CONTAINER_OUTPUT_FILE}"

log "\n${GREEN}Report generated successfully!${NC}"
echo "Output has been saved to: ${HOST_OUTPUT_FILE}"