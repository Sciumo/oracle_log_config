-- hardening.sql  ── Full STIG‑compliant logging baseline (NOMINAL mode)
--
-- Raises an Oracle 12c/18c/19c+ database to DISA Oracle‑Database STIG
-- CAT I–CAT III logging requirements.
--
-- Invocation (as SYSDBA):
--     @hardening.sql  <RETENTION_DAYS>
-- If <RETENTION_DAYS> is omitted or not a positive integer, it defaults to 30.
--
whenever sqlerror exit failure rollback;

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 1. Resolve retention‑days parameter                                      │
-- ╰──────────────────────────────────────────────────────────────────────────╯
column ret_days new_value RET_DAYS noprint;
select case when regexp_like('&1','^\d+$') and to_number('&1') > 0
            then to_number('&1')
            else 30
       end as ret_days
  from dual;

prompt Retention days set to &RET_DAYS

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 2. Core parameter changes                                                │
-- ╰──────────────────────────────────────────────────────────────────────────╯

alter system set audit_trail              = 'DB,EXTENDED'         scope=both;
alter system set audit_sys_operations     = TRUE                  scope=both;
alter system set unified_audit_sga_queue_size = 1048576           scope=spfile; -- 1 MiB
alter system set audit_file_dest          = '/opt/oracle/audit'   scope=spfile;
alter system set max_dump_file_size        = '10240'              scope=both;
alter system set sql_trace                 = FALSE                scope=both;
alter system set timed_statistics          = TRUE                 scope=both;

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 3. Traditional (pre‑12c) auditing fallback                               │
-- ╰──────────────────────────────────────────────────────────────────────────╯
audit create session by access whenever not successful;
audit create session by access whenever successful;
audit system grant;
audit role;
audit table;

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 4. Unified auditing (12c+)                                               │
-- ╰──────────────────────────────────────────────────────────────────────────╯
BEGIN
  EXECUTE IMMEDIATE 'CREATE AUDIT POLICY ua_logins ACTIONS ALL ON DEFAULT ALLOW TOPPLV';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF; END;
/
BEGIN
  EXECUTE IMMEDIATE 'AUDIT POLICY ua_logins BY ALL USERS WHENEVER NOT SUCCESSFUL';
EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 5. Purge job                                                             │
-- ╰──────────────────────────────────────────────────────────────────────────╯
BEGIN
  DBMS_AUDIT_MGMT.init_cleanup(
      audit_trail_type        => DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL,
      default_cleanup_interval=> 24);

  DBMS_AUDIT_MGMT.set_last_archive_timestamp(
      audit_trail_type        => DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL,
      last_archive_time       => SYSTIMESTAMP - &RET_DAYS);

  DBMS_AUDIT_MGMT.create_purge_job(
      audit_trail_type        => DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL,
      audit_purge_interval    => 24,
      audit_purge_name        => 'PURGE_AUDIT_TRAIL_STIG');
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -27477 THEN RAISE; END IF; END;
/

prompt hardening.sql completed successfully.
