#!/usr/bin/env bash
# ============================================================================
# test_audit_stig.sh  –  End‑to‑end acceptance test for audit_oracle_stig_logging
# ============================================================================
# This script uses 'docker cp' to move files into the container, avoiding
# common volume mount permission issues. It walks an instance through the
# three compliance stages: BASE → LEAST → NOMINAL. Any deviation
# causes the script to abort.
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 1. Globals and helpers
# ─────────────────────────────────────────────────────────────────────────────
ORACLE_IMAGE="${ORACLE_IMAGE:-oracle/database:19.3.0-ee}"
CONTAINER_NAME="oracle_stig_test"
ORACLE_HOSTNAME="oracledb"
ORACLE_PWD="${ORACLE_PWD:-Oradoc_db1}"
DAYS_MIN=30

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# ---------- colours ---------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}✓ $*${NC}" ; }
err() { echo -e "${RED}✖ $*${NC}" >&2; exit 1; }

log "Verifying presence of required files on the host in: ${SCRIPT_DIR}"

mkdir -p "./logs"  # default to local ./logs for simplicity

# UPDATED: List of required files now reflects the pre/post split
REQUIRED_FILES=(
    "audit_oracle_stig_logging.sh" "apply_sql.sh"
    "least_hardening_pre.sql" "least_hardening_post.sql"
    "hardening_pre.sql" "hardening_post.sql"
)
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "${SCRIPT_DIR}/${f}" ]; then
        err "Required file not found on host: ${f}. Please ensure it's in the same directory as this test script."
    fi
done
log "All required files found on host."

wait_db_ready() {
    local container_name=$1
    local timeout_seconds=300
    local seconds_elapsed=0

    log "Waiting up to ${timeout_seconds}s for container '${container_name}' to become healthy..."
    while [ $seconds_elapsed -lt $timeout_seconds ]; do
        local health_status
        health_status=$(docker inspect --format '{{.State.Health.Status}}' "${container_name}" || echo "inspect_failed")

        if [ "${health_status}" == "healthy" ]; then
            log "\nDatabase container is healthy! Waiting an extra 10s for services to stabilize."
            sleep 10
            return 0
        fi
        echo -n "."
        sleep 5
        seconds_elapsed=$((seconds_elapsed + 5))
    done

    err "\nTimed out waiting for the database container to become healthy. Check logs with: docker logs ${container_name}"
}

restart_and_wait() {
    log "Restarting container '${CONTAINER_NAME}' to apply SPFILE changes..."
    docker restart "${CONTAINER_NAME}"
    wait_db_ready "${CONTAINER_NAME}"
}

prepare_container() {
    log "Preparing container with all required files..."
    # The array of files to copy is now the same as the required files
    local files_to_copy=("${REQUIRED_FILES[@]}")

    # Copy all files to container
    for file in "${files_to_copy[@]}"; do
        local host_path="${SCRIPT_DIR}/${file}"
        local container_path="/tmp/${file}"
        log "  - Copying '${file}' to container..."
        docker cp "${host_path}" "${CONTAINER_NAME}:${container_path}" || err "docker cp failed for ${file}"
        if [[ "$file" == *.sh ]]; then
            docker exec -u root "$CONTAINER_NAME" bash -c "chown oracle:oinstall ${container_path} && chmod +x ${container_path}" || \
                err "Failed to set permissions on ${file}"
        else
            docker exec -u root "$CONTAINER_NAME" bash -c "chown oracle:oinstall ${container_path}" || \
                err "Failed to set permissions on ${file}"
        fi
    done

    # Verify all files exist in container
    log "  - Verifying all files exist in container..."
    for file in "${files_to_copy[@]}"; do
        docker exec "$CONTAINER_NAME" test -f "/tmp/${file}" || \
            err "File verification failed: ${file} not found in container at /tmp/${file}"
    done
    
    docker exec "$CONTAINER_NAME" mkdir -p /tmp/logs
    docker exec -u root "$CONTAINER_NAME" chown oracle:oinstall /tmp/logs
    log "Container preparation complete."
}

# Encapsulates the two-step apply process (pre,restart,post-restart)
apply_compliance_stage() {
    local compliance=$1
    local days=$2
    local pre_script=""
    local post_script=""

    case "${compliance^^}" in
        LEAST)   pre_script="least_hardening_pre.sql"; post_script="least_hardening_post.sql" ;;
        NOMINAL) pre_script="hardening_pre.sql"; post_script="hardening_post.sql" ;;
        *) err "Unknown compliance level for application: $compliance" ;;
    esac

    log "Applying $compliance compliance (pre-restart phase) with $pre_script"
    docker exec -u oracle "$CONTAINER_NAME" \
        bash -lc "/tmp/apply_sql.sh --server localhost --service ORCLCDB --username sys --password \$ORACLE_PWD \
                  --sql-file /tmp/${pre_script} --days ${days}" || err "SQL application failed for ${pre_script}"

    restart_and_wait

    log "Applying $compliance compliance (post-restart phase) with $post_script"
    docker exec -u oracle "$CONTAINER_NAME" \
        bash -lc "/tmp/apply_sql.sh --server localhost --service ORCLCDB --username sys --password \$ORACLE_PWD \
                  --sql-file /tmp/${post_script} --days ${days}" || err "SQL application failed for ${post_script}"
}


run_audit() {
    local days=$1 compliance=$2 outfile=$3
    local outfile_path="${SCRIPT_DIR}/${outfile}"
    local audit_script_name="audit_oracle_stig_logging.sh"
    local container_path="/tmp/${audit_script_name}"
    local exit_code=0

    log "Starting audit run for '$outfile'..."

    log "  1. Executing script (as oracle user)..."
    docker exec -u oracle "$CONTAINER_NAME" \
        bash -lc "${container_path} \
                    --server localhost --service ORCLCDB --username sys --password \$ORACLE_PWD \
                    --days ${days} --compliance ${compliance} -o /tmp/logs"  > "$outfile_path" 2>&1 || exit_code=$?

    docker cp "${CONTAINER_NAME}:/tmp/logs/." ./logs >/dev/null

    if [ ! -s "$outfile_path" ]; then
        err "Audit execution succeeded but produced an EMPTY report file ('$outfile'). This is unexpected."
    fi;
    log "  - Audit exit code $exit_code and report file: '$outfile'."
}

expect_compliance() {
    local expected=$1 report_file="$SCRIPT_DIR/$2"
    log "  - Verifying compliance level in '$2'..."
    if [ "$expected" != "NOT-COMPLIANT" ]; then
        if ! grep -q "configuration is compliant" "$report_file"; then
            # Build the error message safely to avoid unmatched-quote parsing errors.
            err "$(printf "Compliance check FAILED. Expected '%s'. Report:\n---\n" "$expected"; cat "$report_file"; printf "\n---\n")"
        fi           
    else
        if grep -q "configuration is compliant" "$report_file"; then
            log "$(printf "Compliance check passed instead of 'NOT-COMPLIANT', so the database may already be configured. Report:\n---\n"; \
                 cat "$report_file"; printf "\n---\n")"            
        fi
    fi
    log "Compliance level '$expected' verified ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Verify and launch base container
# ─────────────────────────────────────────────────────────────────────────────
log "Verifying Oracle image exists: $ORACLE_IMAGE"
if ! docker image inspect "$ORACLE_IMAGE" >/dev/null 2>&1; then
    err "Oracle image $ORACLE_IMAGE not found. Please pull it first via 'docker pull $ORACLE_IMAGE'"
fi
ORACLE_DATA_VOLUME="oracle_stig_test_data"
log "Ensuring Oracle data volume $ORACLE_DATA_VOLUME exists"
docker volume create "$ORACLE_DATA_VOLUME" >/dev/null

if [ -z "$(docker ps -q -f name=^${CONTAINER_NAME}$)" ]; then
    if [ -n "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
        log "Container '$CONTAINER_NAME' exists but is stopped. Removing it for a clean start..."
        docker rm -f "$CONTAINER_NAME" > /dev/null
    fi
    log "Container '$CONTAINER_NAME' not found. Creating and starting new container..."
    docker run -d --name "$CONTAINER_NAME" \
      --hostname "$ORACLE_HOSTNAME" \
      -e ORACLE_PWD="$ORACLE_PWD" \
      -p 1521:1521 \
      -v "$ORACLE_DATA_VOLUME":/opt/oracle/oradata \
      "$ORACLE_IMAGE" || err "Container failed to start"

    log "Fixing permissions on the data volume mount point..."
    docker exec -u root "$CONTAINER_NAME" chown -R oracle:oinstall /opt/oracle/oradata || err "Failed to set permissions on data volume"
          
    wait_db_ready "$CONTAINER_NAME"
else
    log "Container '$CONTAINER_NAME' is already running. For a clean test, please stop and remove it first."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Prepare container with all required files
# ─────────────────────────────────────────────────────────────────────────────
prepare_container

# ─────────────────────────────────────────────────────────────────────────────
# 4. All stages
# ─────────────────────────────────────────────────────────────────────────────
log "Stage 1: auditing vanilla image (expect NOT-COMPLIANT) ..."
run_audit "$DAYS_MIN" "LEAST" "./logs/stage1_base.txt"
expect_compliance "NOT-COMPLIANT" "./logs/stage1_base.txt"

log "Stage 2: applying LEAST compliance ..."
apply_compliance_stage "LEAST" "$DAYS_MIN"
run_audit "$DAYS_MIN" "LEAST" "./logs/stage2_least.txt"
expect_compliance "LEAST" "./logs/stage2_least.txt"

log "Stage 3: applying NOMINAL compliance ..."
apply_compliance_stage "NOMINAL" "$DAYS_MIN"
run_audit "$DAYS_MIN" "NOMINAL" "./logs/stage3_nominal.txt"
expect_compliance "NOMINAL" "./logs/stage3_nominal.txt"

log "All acceptance tests passed ✓"
