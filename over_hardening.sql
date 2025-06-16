-- over_hardening.sql  ── Deliberately EXCESSIVE logging configuration
--
-- WARNING:  This script turns on every mainstream Oracle auditing and
--           diagnostic trace knob, sets huge retention, and removes dump
--           size caps.  It is intended ONLY for negative‑test scenarios in
--           the audit harness.  Do NOT run in production.
--
-- Invocation (as SYSDBA):
--     @over_hardening.sql  <RETENTION_DAYS>
-- If <RETENTION_DAYS> is omitted or not a positive integer, it defaults to 365.
--
whenever sqlerror exit failure rollback;

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 1. Resolve retention‑days parameter                                      │
-- ╰──────────────────────────────────────────────────────────────────────────╯
column ret_days new_value RET_DAYS noprint;
select case when regexp_like('&1','^\d+$') and to_number('&1') > 0
            then to_number('&1')
            else 365
       end as ret_days
  from dual;

prompt Retention days set to &RET_DAYS (EXCESSIVE mode)

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 2. Parameters – go well beyond STIG                                      │
-- ╰──────────────────────────────────────────────────────────────────────────╯

-- Enable the most verbose audit trail and force it to XML,EXTENDED.
alter system set audit_trail                     = 'XML,EXTENDED'          scope=spfile;
-- Keep every SYS operation.
alter system set audit_sys_operations            = TRUE                    scope=both;
-- Increase unified audit memory to 16 MiB.
alter system set unified_audit_sga_queue_size    = 16777216                scope=spfile;
-- Raise AUDIT_FILE_DEST to a dedicated mount.
alter system set audit_file_dest                 = '/opt/oracle/audit'     scope=spfile;

-- Remove any cap on diagnostic dumps.
alter system set max_dump_file_size              = 'UNLIMITED'             scope=both;
-- Force SQL trace on for **every** session.
alter system set sql_trace                       = TRUE                    scope=both;
-- Ensure timing data is collected.
alter system set timed_statistics                = TRUE                    scope=both;
-- Turn on bind/‑wait tracing at system level.
alter system set sql_trace_waits                 = TRUE                    scope=both;
alter system set sql_trace_binds                 = TRUE                    scope=both;

-- Enable heavy optimiser tracing and wait‑event capture (warning: overhead!)
alter system set events '10046 trace name context forever, level 12';
alter system set events '10053 trace name context forever';

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 3. Blanket auditing rules                                                │
-- ╰──────────────────────────────────────────────────────────────────────────╯

-- Traditional blanket audit (duplicates unified policies but inflates trail)
audit all by access;

-- Unified audit that captures every action by every user (massive volume)
DECLARE
  PROCEDURE ensure_policy(p_name IN VARCHAR2, p_def IN VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE 'CREATE AUDIT POLICY '||p_name||' '||p_def;
  EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF;
  END;
BEGIN
  ensure_policy('UA_ALL_ACTIONS', 'ALL ACTIONS');
  EXECUTE IMMEDIATE 'AUDIT POLICY UA_ALL_ACTIONS BY ALL';
END;
/

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 4. Audit‐trail purge window – massive                                    │
-- ╰──────────────────────────────────────────────────────────────────────────╯
BEGIN
  DBMS_AUDIT_MGMT.init_cleanup(
      audit_trail_type         => DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL,
      default_cleanup_interval => 24);

  DBMS_AUDIT_MGMT.set_last_archive_timestamp(
      audit_trail_type         => DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL,
      last_archive_time        => SYSTIMESTAMP - &RET_DAYS);

  DBMS_AUDIT_MGMT.create_purge_job(
      audit_trail_type         => DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL,
      audit_purge_interval     => 24,
      audit_purge_name         => 'PURGE_AUDIT_TRAIL_EXCESS');
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -27477 THEN RAISE; END IF; END;
/

prompt over_hardening.sql completed ‑ database now in EXCESSIVE logging mode.
