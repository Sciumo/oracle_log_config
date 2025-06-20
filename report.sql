-- ============================================================================
-- report.sql – Comprehensive Oracle Logging & Auditing Configuration Report
-- ============================================================================
-- This script queries a wide range of data dictionary views to generate a
-- detailed report on the database's logging, auditing, tracing, and space
-- usage configurations.
--
-- INVOCATION:
-- This script is designed to be run from SQL*Plus. It expects one argument:
-- the path for the output spool file.
--
-- Example:
--   sqlplus user/pass@db @report.sql /path/to/my_report.txt
-- ============================================================================

SET PAGESIZE 1000
SET LINESIZE 200
SET TRIMSPOOL ON
SET ECHO OFF
SET FEEDBACK OFF
SET HEADING ON

-- The first argument passed to this script will be used as the output file name
SPOOL &1

PROMPT ===============================================
PROMPT ORACLE DATABASE LOGGING CONFIGURATION REPORT
PROMPT ===============================================
PROMPT
PROMPT Report generated at:
SELECT to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS') as report_time FROM dual;

PROMPT
PROMPT Database Information:
COLUMN instance_name FORMAT A20
COLUMN host_name FORMAT A30
COLUMN version FORMAT A20
SELECT instance_name, host_name, version, startup_time, database_status
FROM v$instance;

PROMPT
PROMPT Database Name and ID:
COLUMN db_name FORMAT A20
COLUMN log_mode FORMAT A15
COLUMN open_mode FORMAT A15
SELECT name as db_name, dbid, log_mode, open_mode
FROM v$database;

PROMPT
PROMPT ===============================================
PROMPT AUDIT CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Current Audit Parameters:
COLUMN name FORMAT A40
COLUMN value FORMAT A60
SELECT name, value
FROM v$parameter
WHERE name LIKE '%audit%'
ORDER BY name;

PROMPT
PROMPT Statement Audit Options (Traditional Auditing):
COLUMN user_name FORMAT A30
COLUMN audit_option FORMAT A40
SELECT user_name, audit_option, success, failure
FROM dba_stmt_audit_opts
ORDER BY user_name, audit_option;

PROMPT
PROMPT Privilege Audit Options (Traditional Auditing):
COLUMN privilege FORMAT A40
SELECT user_name, privilege, success, failure
FROM dba_priv_audit_opts
ORDER BY user_name, privilege;

PROMPT
PROMPT Object Audit Options (Traditional Auditing):
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
PROMPT Enabled Unified Auditing Policies (12c+):
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
PROMPT ===============================================
PROMPT ALERT LOG AND DIAGNOSTIC CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Alert Log and Diagnostic Parameters:
SELECT name, value
FROM v$parameter
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
FROM v$diag_info;

PROMPT
PROMPT ===============================================
PROMPT ARCHIVE LOG AND REDO LOG CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Archive Log Parameters:
SELECT name, value
FROM v$parameter
WHERE name LIKE '%archive%' OR name LIKE '%log_archive%'
ORDER BY name;

PROMPT
PROMPT Redo Log Groups and Sizes:
SELECT l.group#, l.thread#, l.sequence#, l.bytes/1024/1024 as size_mb,
       l.blocksize, l.members, l.status
FROM v$log l
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
FROM v$recovery_file_dest;

PROMPT
PROMPT Archive Log Generation Per Day (Last 7 Days):
COLUMN day FORMAT A15
COLUMN generated_gb FORMAT 999,999.99
SELECT to_char(trunc(completion_time), 'YYYY-MM-DD') AS day,
       round(sum(blocks * block_size) / 1024 / 1024 / 1024, 2) AS generated_gb,
       count(*) as file_count
FROM v$archived_log
WHERE completion_time > SYSDATE - 7
GROUP BY trunc(completion_time)
ORDER BY day;

PROMPT
PROMPT Redo Log Switches Per Hour (Last 24 Hours):
COLUMN hour FORMAT A15
SELECT to_char(first_time, 'YYYY-MM-DD HH24') || ':00' AS hour,
       count(*) AS switches
FROM v$log_history
WHERE first_time > SYSDATE - 1
GROUP BY to_char(first_time, 'YYYY-MM-DD HH24')
ORDER BY hour;

PROMPT
PROMPT Large Diagnostic Files (>10MB) - Includes Trace and Audit XML Files:
COLUMN trace_filename FORMAT A100
SELECT trace_filename,
       sizeblks*block_size/1024/1024 as size_mb,
       to_char(change_time, 'YYYY-MM-DD HH24:MI:SS') as last_modified
FROM v$diag_trace_file
WHERE sizeblks*block_size > 10*1024*1024
ORDER BY sizeblks DESC;

SPOOL OFF
SET FEEDBACK ON
SET ECHO ON
EXIT;