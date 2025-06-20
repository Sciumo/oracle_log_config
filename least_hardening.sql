-- least_hardening.sql  ── Minimal STIG-compliant logging baseline (LEAST mode)
--
-- Usage (as SYSDBA inside the target database):
--     @least_hardening.sql 30  -- keeps audit records for >=30 days
--
-- Positional parameter 1: DAYS – positive integer retention threshold.
-- If not supplied, defaults to 30.

whenever sqlerror exit failure rollback;

-- Handle parameter gracefully with default
column ret_days new_value RETENTION_DAYS noprint;
select case when regexp_like('&1','^\d+') and to_number('&1') > 0
            then to_number('&1')
            else 30
       end as ret_days
  from dual;

COL now_date NEW_VALUE NOW_DATE NOPRINT
SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') now_date FROM dual;
PROMPT Applying LEAST STIG hardening - &RETENTION_DAYS day retention - &NOW_DATE

-- 1. Set the audit trail to the smallest value still acceptable to DISA STIG.
--    STIG allows OS, DB, DB,EXTENDED, XML, etc.  We choose DB (no EXTENDED).
ALTER SYSTEM SET audit_trail = 'DB' SCOPE=SPFILE;

-- 2. Ensure SYS operations are audited (CAT II requirement).
ALTER SYSTEM SET audit_sys_operations = TRUE SCOPE=SPFILE;

-- 3. Enable minimal auditing required by STIG
-- ALL login attempts (successful and failed) are required for STIG compliance
AUDIT CREATE SESSION BY ACCESS;

-- 4. Configure a purge window so the audit trail is retained for at least the
--    specified number of days but not indefinitely.
PROMPT Applying LEAST STIG hardening - DBMS_AUDIT_MGMT.INIT_CLEANUP DBMS_AUDIT_MGMT.AUDIT_TRAIL_AUD_STD
DECLARE
  v_days  PLS_INTEGER := &RETENTION_DAYS;
  v_job_exists NUMBER;
BEGIN
  -- Initialize cleanup if not already done
  BEGIN
    DBMS_AUDIT_MGMT.INIT_CLEANUP(
      audit_trail_type => DBMS_AUDIT_MGMT.AUDIT_TRAIL_AUD_STD,
      default_cleanup_interval => 24
    );
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE IN (-46267, -46263) THEN -- Handle both "already initialized" errors
        NULL;
      ELSE
        RAISE;
      END IF;
  END;
  
  -- Set archive timestamp
  DBMS_AUDIT_MGMT.SET_LAST_ARCHIVE_TIMESTAMP(
    audit_trail_type => DBMS_AUDIT_MGMT.AUDIT_TRAIL_AUD_STD,
    last_archive_time => SYSTIMESTAMP - v_days
  );
  
  -- Check if purge job already exists in SYS schema
  SELECT COUNT(*) INTO v_job_exists
  FROM dba_scheduler_jobs
  WHERE owner = 'SYS' AND job_name = 'PURGE_AUDIT_TRAIL_LEAST_STIG';
  
  IF v_job_exists = 0 THEN
    -- Create purge job if it doesn't exist
    BEGIN
      DBMS_AUDIT_MGMT.CREATE_PURGE_JOB(
        audit_trail_type => DBMS_AUDIT_MGMT.AUDIT_TRAIL_AUD_STD,
        audit_trail_purge_interval => 24,
        audit_trail_purge_name => 'PURGE_AUDIT_TRAIL_LEAST_STIG',
        use_last_arch_timestamp => TRUE
      );
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE = -46254 THEN -- Job already exists (race condition)
          NULL;
        ELSE
          RAISE;
        END IF;
    END;
  ELSE
    -- Update existing job, handle case where job is missing or broken
    BEGIN
      DBMS_SCHEDULER.SET_ATTRIBUTE(
        name => 'SYS.PURGE_AUDIT_TRAIL_LEAST_STIG',
        attribute => 'REPEAT_INTERVAL',
        value => 'FREQ=HOURLY;INTERVAL=24'
      );
      DBMS_SCHEDULER.ENABLE('SYS.PURGE_AUDIT_TRAIL_LEAST_STIG');
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE = -27476 THEN -- Job does not exist
          -- Recreate the job
          DBMS_AUDIT_MGMT.CREATE_PURGE_JOB(
            audit_trail_type => DBMS_AUDIT_MGMT.AUDIT_TRAIL_AUD_STD,
            audit_trail_purge_interval => 24,
            audit_trail_purge_name => 'PURGE_AUDIT_TRAIL_LEAST_STIG',
            use_last_arch_timestamp => TRUE
          );
        ELSE
          RAISE;
        END IF;
    END;
  END IF;
END;
/

PROMPT LEAST hardening complete. Bounce the instance to activate parameter changes.
exit success;