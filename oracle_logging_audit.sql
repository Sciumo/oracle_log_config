-- Oracle Logging, Audit, and Trace Configuration Documentation
-- Generated on: &_DATE
-- Database: &_CONNECT_IDENTIFIER

SET PAGESIZE 1000
SET LINESIZE 200
SET TRIMSPOOL ON
SET ECHO OFF
SET FEEDBACK OFF
SET HEADING ON

SPOOL oracle_logging_config_&_DATE..txt

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
PROMPT Object Audit Options:
SELECT owner, object_name, object_type, alt, aud, com, del, gra, ind, ins, loc, ren, sel, upd, ref, exe, cre, rea, wri, fbk
FROM dba_obj_audit_opts 
WHERE alt != '-/-' OR aud != '-/-' OR com != '-/-' OR del != '-/-' 
   OR gra != '-/-' OR ind != '-/-' OR ins != '-/-' OR loc != '-/-'
   OR ren != '-/-' OR sel != '-/-' OR upd != '-/-' OR ref != '-/-'
   OR exe != '-/-' OR cre != '-/-' OR rea != '-/-' OR wri != '-/-' OR fbk != '-/-'
ORDER BY owner, object_name;

PROMPT
PROMPT Unified Auditing Policies (12c+):
SELECT policy_name, enabled_option, entity_name, entity_type, success, failure
FROM audit_unified_enabled_policies
ORDER BY policy_name, entity_name;

PROMPT
PROMPT Current Audit File Sizes:
SELECT file_name, bytes/1024/1024 as size_mb 
FROM dba_audit_trail 
WHERE file_name IS NOT NULL
GROUP BY file_name
ORDER BY bytes DESC;

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
       s.program, s.machine
FROM v$session s 
WHERE s.username IS NOT NULL
ORDER BY s.username, s.sid;

PROMPT
PROMPT Active Trace Files:
SELECT trace_filename, change_time, sizeblks*block_size/1024 as size_kb
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
SELECT name, value, description 
FROM v$parameter 
WHERE name LIKE '%log%' AND name LIKE '%alert%'
   OR name LIKE '%diagnostic%'
   OR name LIKE '%dump%'
   OR name IN ('log_checkpoints_to_alert', 'log_archive_trace')
ORDER BY name;

PROMPT
PROMPT ADR (Automatic Diagnostic Repository) Information:
SELECT inst_id, comp_id, adr_home, adr_base, banner 
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
SELECT dest_id, status, destination, target, schedule, process, delay_mins,
       quota_size, quota_used
FROM v$archive_dest 
WHERE status != 'INACTIVE';

PROMPT
PROMPT Current Archive Log Usage:
SELECT dest_id, archived, applied, deleted, status
FROM v$archive_dest_status;

PROMPT
PROMPT ===============================================
PROMPT REDO LOG CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Redo Log Groups and Sizes:
SELECT l.group#, l.thread#, l.sequence#, l.bytes/1024/1024 as size_mb, 
       l.blocksize, l.members, l.status
FROM v$log l
ORDER BY l.group#;

PROMPT
PROMPT Redo Log Members (Files):
SELECT group#, member, status, type 
FROM v$logfile 
ORDER BY group#, member;

PROMPT
PROMPT ===============================================
PROMPT SPACE USAGE SUMMARY
PROMPT ===============================================

PROMPT
PROMPT Archive Log Space Usage:
SELECT dest_name, space_limit/1024/1024/1024 as limit_gb, 
       space_used/1024/1024/1024 as used_gb,
       round(space_used/space_limit*100,2) as pct_used
FROM v$recovery_file_dest;

PROMPT
PROMPT Diagnostic Destination Space:
SELECT sum(sizeblks*block_size)/1024/1024/1024 as total_trace_gb
FROM v$diag_trace_file;

PROMPT
PROMPT ===============================================
PROMPT RECOMMENDATIONS
PROMPT ===============================================

PROMPT
PROMPT Large Trace Files (>10MB):
SELECT trace_filename, sizeblks*block_size/1024/1024 as size_mb, change_time
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
SELECT trunc(timestamp) as audit_date, count(*) as records
FROM dba_audit_trail 
WHERE timestamp > SYSDATE - 7
GROUP BY trunc(timestamp)
ORDER BY audit_date DESC;

PROMPT
PROMPT Report completed at: 
SELECT to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS') as report_time FROM dual;

SPOOL OFF
SET FEEDBACK ON
SET ECHO ON