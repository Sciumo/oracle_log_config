#!/bin/bash

# Oracle Logging Configuration Documentation - Bash Script
# Usage: ./get_oracle_logging_config.sh -s hostname -d ORCL -u system [-p password] [-P 1521] [-o /output/dir]

# Default values
PORT="1521"
OUTPUT_DIR="."
SQLPLUS_PATH="sqlplus"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Function to show usage
usage() {
    echo "Usage: $0 -s server -d service -u username [-p password] [-P port] [-o output_dir] [-x sqlplus_path]"
    echo ""
    echo "Required parameters:"
    echo "  -s server      Database server hostname or IP"
    echo "  -d service     Database service name"
    echo "  -u username    Database username"
    echo ""
    echo "Optional parameters:"
    echo "  -p password    Database password (will prompt if not provided)"
    echo "  -P port        Database port (default: 1521)"
    echo "  -o output_dir  Output directory (default: current directory)"
    echo "  -x sqlplus_path Path to sqlplus executable (default: sqlplus)"
    echo "  -h             Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -s oradb01 -d PROD -u system -P 1521 -o /tmp/oracle_audit"
    exit 1
}

# Parse command line arguments
while getopts "s:d:u:p:P:o:x:h" opt; do
    case $opt in
        s) SERVER="$OPTARG" ;;
        d) SERVICE="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        P) PORT="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        x) SQLPLUS_PATH="$OPTARG" ;;
        h) usage ;;
        \?) echo "Invalid option -$OPTARG" >&2; usage ;;
    esac
done

# Check required parameters
if [ -z "$SERVER" ] || [ -z "$SERVICE" ] || [ -z "$USERNAME" ]; then
    print_color $RED "ERROR: Missing required parameters"
    usage
fi

print_color $GREEN "Oracle Logging Configuration Documentation Script"
print_color $GREEN "=================================================="

# Check if SQL*Plus is available
if ! command -v "$SQLPLUS_PATH" &> /dev/null; then
    print_color $RED "ERROR: SQL*Plus not found at path: $SQLPLUS_PATH"
    print_color $YELLOW "Please ensure Oracle Client is installed and SQL*Plus is in PATH"
    exit 1
fi

# Create output directory if it doesn't exist
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
    if [ $? -ne 0 ]; then
        print_color $RED "ERROR: Could not create output directory: $OUTPUT_DIR"
        exit 1
    fi
fi

# Get password if not provided
if [ -z "$PASSWORD" ]; then
    echo -n "Enter password for $USERNAME: "
    read -s PASSWORD
    echo
fi

# Create timestamp for file naming
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SQL_FILE="$OUTPUT_DIR/oracle_logging_audit_$TIMESTAMP.sql"
OUTPUT_FILE="$OUTPUT_DIR/oracle_logging_config_$TIMESTAMP.txt"
LOG_FILE="$OUTPUT_DIR/oracle_audit_$TIMESTAMP.log"

print_color $CYAN "Configuration:"
echo "  Server: $SERVER"
echo "  Port: $PORT"
echo "  Service: $SERVICE"
echo "  Username: $USERNAME"
echo "  Output Directory: $OUTPUT_DIR"
echo "  SQL File: $SQL_FILE"
echo "  Output File: $OUTPUT_FILE"

# Create the SQL script
cat > "$SQL_FILE" << 'EOF'
-- Oracle Logging, Audit, and Trace Configuration Documentation
-- Generated on: &_DATE
-- Database: &_CONNECT_IDENTIFIER

SET PAGESIZE 1000
SET LINESIZE 200
SET TRIMSPOOL ON
SET ECHO OFF
SET FEEDBACK OFF
SET HEADING ON

SPOOL &1

PROMPT ===============================================
PROMPT ORACLE DATABASE LOGGING CONFIGURATION REPORT
PROMPT ===============================================
PROMPT
PROMPT Database Information:
SELECT instance_name, host_name, version, startup_time, database_status 
FROM v$instance;

PROMPT
PROMPT Database Name and ID:
SELECT name as db_name, dbid, log_mode, open_mode 
FROM v$database;

PROMPT
PROMPT ===============================================
PROMPT AUDIT CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Current Audit Parameters:
SELECT name, value, description 
FROM v$parameter 
WHERE name LIKE '%audit%' 
ORDER BY name;

PROMPT
PROMPT Statement Audit Options (What statements are being audited):
SELECT user_name, audit_option, success, failure 
FROM dba_stmt_audit_opts 
ORDER BY user_name, audit_option;

PROMPT
PROMPT Privilege Audit Options:
SELECT user_name, privilege, success, failure 
FROM dba_priv_audit_opts 
ORDER BY user_name, privilege;

PROMPT
PROMPT Object Audit Options (Active only):
SELECT owner, object_name, object_type, alt, aud, com, del, gra, ind, ins, loc, ren, sel, upd, ref, exe, cre, rea, wri, fbk
FROM dba_obj_audit_opts 
WHERE alt != '-/-' OR aud != '-/-' OR com != '-/-' OR del != '-/-' 
   OR gra != '-/-' OR ind != '-/-' OR ins != '-/-' OR loc != '-/-'
   OR ren != '-/-' OR sel != '-/-' OR upd != '-/-' OR ref != '-/-'
   OR exe != '-/-' OR cre != '-/-' OR rea != '-/-' OR wri != '-/-' OR fbk != '-/-'
ORDER BY owner, object_name;

PROMPT
PROMPT Unified Auditing Policies (12c+):
WHENEVER SQLERROR CONTINUE
SELECT policy_name, enabled_option, entity_name, entity_type, success, failure
FROM audit_unified_enabled_policies
ORDER BY policy_name, entity_name;
WHENEVER SQLERROR EXIT FAILURE

PROMPT
PROMPT ===============================================
PROMPT SQL TRACING CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT SQL Trace and Timing Parameters:
SELECT name, value, description 
FROM v$parameter 
WHERE name IN ('sql_trace', 'timed_statistics', 'max_dump_file_size', 
               'user_dump_dest', 'background_dump_dest', 'diagnostic_dest',
               'sql_trace_waits', 'sql_trace_binds')
ORDER BY name;

PROMPT
PROMPT Event Parameters (10046, 10053, etc.):
SELECT name, value 
FROM v$parameter 
WHERE name LIKE '%event%' AND value IS NOT NULL;

PROMPT
PROMPT Current Session Trace Settings:
SELECT s.sid, s.serial#, s.username, s.sql_trace, s.sql_trace_waits, s.sql_trace_binds,
       substr(s.program,1,20) as program, substr(s.machine,1,15) as machine
FROM v$session s 
WHERE s.username IS NOT NULL
ORDER BY s.username, s.sid;

PROMPT
PROMPT Active Trace Files (Last 24 hours):
SELECT trace_filename, change_time, round(sizeblks*block_size/1024,1) as size_kb
FROM v$diag_trace_file 
WHERE trace_filename LIKE '%.trc'
  AND change_time > SYSDATE - 1
ORDER BY change_time DESC;

PROMPT
PROMPT ===============================================
PROMPT ALERT LOG AND DIAGNOSTIC CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Alert Log and Diagnostic Parameters:
SELECT name, value, substr(description,1,50) as description
FROM v$parameter 
WHERE (name LIKE '%log%' AND name LIKE '%alert%')
   OR name LIKE '%diagnostic%'
   OR name LIKE '%dump%'
   OR name IN ('log_checkpoints_to_alert', 'log_archive_trace')
ORDER BY name;

PROMPT
PROMPT ADR (Automatic Diagnostic Repository) Information:
SELECT inst_id, comp_id, substr(adr_home,1,60) as adr_home, substr(adr_base,1,40) as adr_base
FROM v$diag_info;

PROMPT
PROMPT ===============================================
PROMPT ARCHIVE LOG CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Archive Log Parameters:
SELECT name, value 
FROM v$parameter 
WHERE name LIKE '%archive%' OR name LIKE '%log_archive%'
ORDER BY name;

PROMPT
PROMPT Archive Log Destinations:
SELECT dest_id, status, substr(destination,1,50) as destination, target, schedule, process, delay_mins
FROM v$archive_dest 
WHERE status != 'INACTIVE';

PROMPT
PROMPT Archive Log Destination Status:
SELECT dest_id, archived, applied, deleted, status
FROM v$archive_dest_status
WHERE archived > 0 OR applied > 0;

PROMPT
PROMPT ===============================================
PROMPT REDO LOG CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Redo Log Groups and Sizes:
SELECT l.group#, l.thread#, l.sequence#, round(l.bytes/1024/1024,1) as size_mb, 
       l.blocksize, l.members, l.status
FROM v$log l
ORDER BY l.group#;

PROMPT
PROMPT Redo Log Members (Files):
SELECT group#, substr(member,1,60) as member, status, type 
FROM v$logfile 
ORDER BY group#, member;

PROMPT
PROMPT ===============================================
PROMPT SPACE USAGE SUMMARY
PROMPT ===============================================

PROMPT
PROMPT Archive Log Space Usage:
SELECT dest_name, round(space_limit/1024/1024/1024,2) as limit_gb, 
       round(space_used/1024/1024/1024,2) as used_gb,
       round(space_used/space_limit*100,2) as pct_used
FROM v$recovery_file_dest
WHERE space_limit > 0;

PROMPT
PROMPT Diagnostic Destination Space Summary:
SELECT count(*) as trace_files, 
       round(sum(sizeblks*block_size)/1024/1024,1) as total_trace_mb
FROM v$diag_trace_file;

PROMPT
PROMPT ===============================================
PROMPT RECOMMENDATIONS AND ALERTS
PROMPT ===============================================

PROMPT
PROMPT Large Trace Files (>10MB):
SELECT trace_filename, round(sizeblks*block_size/1024/1024,1) as size_mb, change_time
FROM v$diag_trace_file 
WHERE sizeblks*block_size > 10*1024*1024
ORDER BY sizeblks DESC;

PROMPT
PROMPT Sessions with Tracing Enabled:
SELECT username, count(*) as trace_sessions
FROM v$session 
WHERE sql_trace = 'ENABLED' OR sql_trace_waits = 'TRUE' OR sql_trace_binds = 'TRUE'
GROUP BY username;

PROMPT
PROMPT Audit Records Count by Day (Last 7 days):
WHENEVER SQLERROR CONTINUE
SELECT trunc(timestamp) as audit_date, count(*) as records
FROM dba_audit_trail 
WHERE timestamp > SYSDATE - 7
GROUP BY trunc(timestamp)
ORDER BY audit_date DESC;
WHENEVER SQLERROR EXIT FAILURE

PROMPT
PROMPT Archive Log Generation Rate (Last 24 hours):
SELECT trunc(first_time,'HH24') as hour_start, count(*) as logs_generated,
       round(sum(blocks*block_size)/1024/1024,1) as mb_generated
FROM v$archived_log
WHERE first_time > SYSDATE - 1
GROUP BY trunc(first_time,'HH24')
ORDER BY hour_start DESC;

PROMPT
PROMPT Report completed at: 
SELECT to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS') as report_time FROM dual;

SPOOL OFF
SET FEEDBACK ON
SET ECHO ON
EXIT;
EOF

if [ $? -ne 0 ]; then
    print_color $RED "ERROR: Could not create SQL file: $SQL_FILE"
    exit 1
fi

print_color $GREEN "SQL script created: $SQL_FILE"

# Construct connection string
CONNECTION_STRING="${USERNAME}/${PASSWORD}@${SERVER}:${PORT}/${SERVICE}"

print_color $CYAN "\nExecuting Oracle audit script..."
echo "Start time: $(date)"

# Execute SQL*Plus
"$SQLPLUS_PATH" -S "$CONNECTION_STRING" @"$SQL_FILE" "$OUTPUT_FILE" > "$LOG_FILE" 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    print_color $GREEN "\nScript executed successfully!"
    echo "Output file: $OUTPUT_FILE"
    echo "Log file: $LOG_FILE"
    
    # Show file sizes
    if [ -f "$OUTPUT_FILE" ]; then
        SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null)
        if [ -n "$SIZE" ]; then
            SIZE_KB=$((SIZE / 1024))
            echo "Output file size: ${SIZE_KB} KB"
        fi
    fi
    
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)
        if [ -n "$LOG_SIZE" ]; then
            LOG_SIZE_KB=$((LOG_SIZE / 1024))
            echo "Log file size: ${LOG_SIZE_KB} KB"
        fi
    fi
    
    # Check for any Oracle errors in the output
    if [ -f "$OUTPUT_FILE" ]; then
        ERROR_COUNT=$(grep -c "ORA-" "$OUTPUT_FILE" 2>/dev/null || echo "0")
        if [ "$ERROR_COUNT" -gt 0 ]; then
            print_color $YELLOW "Warning: Found $ERROR_COUNT Oracle errors in output. Check the report for details."
        fi
    fi
    
else
    print_color $RED "ERROR: SQL*Plus exited with code $EXIT_CODE"
    if [ -f "$LOG_FILE" ]; then
        print_color $YELLOW "Check log file for details: $LOG_FILE"
        echo -e "\nLast few lines of log:"
        tail -10 "$LOG_FILE"
    fi
    exit 1
fi

echo -e "\nEnd time: $(date)"

# Cleanup temporary SQL file
rm -f "$SQL_FILE"

print_color $GREEN "\nOracle logging configuration audit completed!"
if [ -f "$OUTPUT_FILE" ]; then
    print_color $YELLOW "To view the report: less '$OUTPUT_FILE'"
    print_color $YELLOW "Or search for specific sections: grep -A 5 'AUDIT CONFIGURATION' '$OUTPUT_FILE'"
fi

# Show quick summary
echo -e "\nQuick Summary:"
if [ -f "$OUTPUT_FILE" ]; then
    echo "- Database: $(grep -A 1 "Database Name and ID:" "$OUTPUT_FILE" | tail -1 | awk '{print $1}' 2>/dev/null)"
    echo "- Audit Trail: $(grep -A 10 "Current Audit Parameters:" "$OUTPUT_FILE" | grep "audit_trail" | awk '{print $2}' 2>/dev/null)"
    echo "- SQL Trace: $(grep -A 10 "SQL Trace and Timing Parameters:" "$OUTPUT_FILE" | grep "sql_trace" | awk '{print $2}' 2>/dev/null)"
    
    # Count active auditing
    AUDIT_COUNT=$(grep -c "SUCCESS" "$OUTPUT_FILE" 2>/dev/null || echo "0")
    echo "- Active audit options: $AUDIT_COUNT"
fi