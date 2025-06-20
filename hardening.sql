-- hardening.sql  ── Full STIG‑compliant logging baseline (NOMINAL mode)
--
-- Raises an Oracle 19c/21c+ database to DISA Oracle‑Database STIG
-- CAT I–CAT III logging requirements.
--
-- Invocation (as SYSDBA):
--     @hardening.sql  <RETENTION_DAYS>
-- If <RETENTION_DAYS> is omitted or not a positive integer, it defaults to 30.
--
whenever sqlerror exit failure rollback;

SET SERVEROUTPUT ON SIZE UNLIMITED;

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
DECLARE
  v_audit_trail VARCHAR2(20);
  v_audit_sys_ops VARCHAR2(10);
  v_sga_queue_size NUMBER;
  v_audit_file_dest VARCHAR2(512);
  v_max_dump_size VARCHAR2(20);
  v_timed_stats VARCHAR2(10);
BEGIN
  SELECT value INTO v_audit_trail FROM v$parameter WHERE name = 'audit_trail';
  SELECT value INTO v_audit_sys_ops FROM v$parameter WHERE name = 'audit_sys_operations';
  SELECT value INTO v_sga_queue_size FROM v$parameter WHERE name = 'unified_audit_sga_queue_size';
  SELECT value INTO v_audit_file_dest FROM v$parameter WHERE name = 'audit_file_dest';
  SELECT value INTO v_max_dump_size FROM v$parameter WHERE name = 'max_dump_file_size';
  SELECT value INTO v_timed_stats FROM v$parameter WHERE name = 'timed_statistics';
  
  -- Debug print statements
  DBMS_OUTPUT.PUT_LINE('v_audit_sys_ops: ' || v_audit_sys_ops);
  DBMS_OUTPUT.PUT_LINE('v_sga_queue_size: ' || v_sga_queue_size);
  DBMS_OUTPUT.PUT_LINE('v_audit_file_dest: ' || v_audit_file_dest);
  DBMS_OUTPUT.PUT_LINE('v_max_dump_size: ' || v_max_dump_size);
  DBMS_OUTPUT.PUT_LINE('v_timed_stats: ' || v_timed_stats);

  DBMS_OUTPUT.PUT_LINE('--- Verifying Audit Configuration for Pure Unified Auditing ---');
  DBMS_OUTPUT.PUT_LINE('Current audit_trail value: ' || v_audit_trail);

  -- GOAL: Ensure traditional auditing is OFF.
  IF UPPER(v_audit_trail) != 'NONE' THEN
    DBMS_OUTPUT.PUT_LINE('WARNING: audit_trail is not NONE. Setting to NONE for pure Unified Auditing compliance.');
    DBMS_OUTPUT.PUT_LINE('A database restart is required for this change to take effect.');
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET audit_trail = NONE SCOPE=SPFILE';
  ELSE
    DBMS_OUTPUT.PUT_LINE('OK: audit_trail is correctly set to NONE.');
  END IF;


  IF UPPER(v_audit_sys_ops) != 'TRUE' THEN
    DBMS_OUTPUT.PUT_LINE('Setting audit_sys_operations = TRUE');
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET audit_sys_operations = TRUE SCOPE=SPFILE';
    DBMS_OUTPUT.PUT_LINE('Altered audit_sys_operations = TRUE');
  END IF;
  IF v_sga_queue_size != 1048576 THEN
    DBMS_OUTPUT.PUT_LINE('Setting unified_audit_sga_queue_size = 1048576');
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET unified_audit_sga_queue_size = 1048576 SCOPE=SPFILE';
    DBMS_OUTPUT.PUT_LINE('Altered unified_audit_sga_queue_size = 1048576');
  END IF;
  IF v_audit_file_dest != '/opt/oracle/audit' THEN
    DBMS_OUTPUT.PUT_LINE('Setting audit_file_dest = ''/opt/oracle/audit''');
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET audit_file_dest = ''/opt/oracle/audit'' SCOPE=SPFILE';
    DBMS_OUTPUT.PUT_LINE('Altered audit_file_dest = ''/opt/oracle/audit''');
  END IF;
  IF v_max_dump_size != '10240' THEN
    DBMS_OUTPUT.PUT_LINE('Setting max_dump_file_size = ''10240''');
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET max_dump_file_size = ''10240'' SCOPE=BOTH';
    DBMS_OUTPUT.PUT_LINE('Altered max_dump_file_size = ''10240''');
  END IF;
  IF UPPER(v_timed_stats) != 'TRUE' THEN
    DBMS_OUTPUT.PUT_LINE('Setting timed_statistics = TRUE ');
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET timed_statistics = TRUE SCOPE=BOTH';
    DBMS_OUTPUT.PUT_LINE('Altered timed_statistics = TRUE ');
  END IF;
END;
/

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 3. Unified auditing (19c+)                                               │
-- ╰──────────────────────────────────────────────────────────────────────────╯
DECLARE
  v_policy_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_policy_exists FROM audit_unified_policies WHERE policy_name = 'UA_LOGINS';
  
  IF v_policy_exists = 0 THEN
    DBMS_OUTPUT.PUT_LINE('Creating Unified Audit Policy for logins...');

    -- STEP 1: Create the policy to define WHAT to audit.
    EXECUTE IMMEDIATE 'CREATE AUDIT POLICY UA_LOGINS ACTIONS LOGON';

    -- STEP 2: Enable the policy and apply the condition (WHEN to audit).
    -- This is the command where 'WHENEVER NOT SUCCESSFUL' is valid.
    DBMS_OUTPUT.PUT_LINE('Audit policy whenever UA_LOGINS not successful...');
    EXECUTE IMMEDIATE 'AUDIT POLICY UA_LOGINS WHENEVER NOT SUCCESSFUL';
    
    DBMS_OUTPUT.PUT_LINE('Policy UA_LOGINS created and enabled for failed logins.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Policy UA_LOGINS already exists. Ensuring it is enabled for failed logins.');
    -- If the policy exists, we still want to ensure the condition is applied.
    -- This command is safe to run even if already set.
    EXECUTE IMMEDIATE 'AUDIT POLICY UA_LOGINS WHENEVER NOT SUCCESSFUL';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error in unified audit policy block: ' || SQLERRM);
    RAISE;
END;
/

-- ╭──────────────────────────────────────────────────────────────────────────╮
-- │ 4. Purge job                                                             │
-- ╰──────────────────────────────────────────────────────────────────────────╯
DECLARE
  v_days PLS_INTEGER := &RET_DAYS;
  v_job_exists NUMBER;
BEGIN
  -- Use AUDIT_TRAIL_ALL. This constant works in both Mixed Mode (pre-restart)
  -- and Pure Unified Mode (post-restart), making it ideal for this script.
  BEGIN
    DBMS_OUTPUT.PUT_LINE('Attempting to initialize audit trail cleanup...');
    DBMS_AUDIT_MGMT.INIT_CLEANUP(
      audit_trail_type       => DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL,
      default_cleanup_interval => 24
    );
    DBMS_OUTPUT.PUT_LINE('Audit cleanup initialization successful.');
  EXCEPTION
    WHEN OTHERS THEN
      -- The following errors mean initialization is already done or partially done,
      -- which is acceptable for this script's purpose. We can safely continue.
      -- -46267: The audit trail is already initialized for cleanup. (Perfect)
      -- -46263: The audit trail type is not supported. (Also ignorable in this context)
      -- -46265: A subset of the audit trail is already initialized.
      IF SQLCODE IN (-46267, -46263, -46265) THEN 
        DBMS_OUTPUT.PUT_LINE('Audit cleanup initialization not needed (SQLCODE ' || SQLCODE || '), which is OK. Continuing...');
        NULL; 
      ELSE 
        RAISE; 
      END IF;
  END;
  
  DBMS_OUTPUT.PUT_LINE('Setting last archive timestamp to T-' || v_days || ' days...');
  DBMS_AUDIT_MGMT.SET_LAST_ARCHIVE_TIMESTAMP(
    audit_trail_type  => DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL,
    last_archive_time => SYSTIMESTAMP - v_days
  );
  
  SELECT COUNT(*) INTO v_job_exists
  FROM dba_scheduler_jobs
  WHERE owner = 'SYS' AND UPPER(job_name) = 'PURGE_AUDIT_TRAIL_STIG';
  
  IF v_job_exists > 0 THEN
      DBMS_OUTPUT.PUT_LINE('Purge job PURGE_AUDIT_TRAIL_STIG exists. Dropping to recreate with correct settings...');
      DBMS_AUDIT_MGMT.DROP_PURGE_JOB(audit_trail_purge_name => 'PURGE_AUDIT_TRAIL_STIG');
  END IF;

  DBMS_OUTPUT.PUT_LINE('Creating new audit purge job PURGE_AUDIT_TRAIL_STIG...');
  DBMS_AUDIT_MGMT.CREATE_PURGE_JOB(
    audit_trail_type         => DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL,
    audit_trail_purge_interval => 24,
    audit_trail_purge_name     => 'PURGE_AUDIT_TRAIL_STIG',
    use_last_arch_timestamp    => TRUE
  );
  DBMS_OUTPUT.PUT_LINE('Purge job configured successfully.');

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error configuring purge job: ' || SQLERRM);
    RAISE;
END;
/

prompt hardening.sql completed successfully.
exit success;