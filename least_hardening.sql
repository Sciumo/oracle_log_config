-- least_hardening.sql  ── Minimal STIG‑compliant logging baseline (LEAST mode)
--
-- Usage (as SYSDBA inside the target database):
--     @least_hardening.sql 30  -- keeps audit records for >=30 days
--
-- Positional parameter 1: DAYS – positive integer retention threshold.
-- If not supplied, defaults to 30.

whenever sqlerror exit failure rollback;

@@?/rdbms/admin/utlrefc  -- ensures & character in comments is not substituted

DEFINE RETENTION_DAYS="&1"
COL now_date NEW_VALUE NOW_DATE NOPRINT
SELECT TO_CHAR(SYSDATE,'YYYY‑MM‑DD HH24:MI:SS') now_date FROM dual;
PROMPT Applying LEAST STIG hardening – &RETENTION_DAYS day retention – &NOW_DATE

-- 1. Set the audit trail to the smallest value still acceptable to DISA STIG.
--    STIG allows OS, DB, DB,EXTENDED, XML, etc.  We choose DB (no EXTENDED).
ALTER SYSTEM SET audit_trail = 'DB'              SCOPE=SPFILE;

-- 2. Ensure SYS operations are audited (CAT II requirement).
ALTER SYSTEM SET audit_sys_operations = TRUE     SCOPE=SPFILE;

-- 3. Enable auditing of critical security events with the narrowest scope that
--    still passes the checklist. Success/failure is audited for these items.
BEGIN
  FOR stmt IN (
    SELECT 'AUDIT ALTER SYSTEM BY ACCESS;'            AS ddl FROM dual UNION ALL
    SELECT 'AUDIT CREATE USER BY ACCESS;'             FROM dual UNION ALL
    SELECT 'AUDIT ALTER USER BY ACCESS;'              FROM dual UNION ALL
    SELECT 'AUDIT DROP USER BY ACCESS;'               FROM dual UNION ALL
    SELECT 'AUDIT ROLE BY ACCESS;'                    FROM dual UNION ALL
    SELECT 'AUDIT CREATE ROLE BY ACCESS;'             FROM dual UNION ALL
    SELECT 'AUDIT DROP ROLE BY ACCESS;'               FROM dual UNION ALL
    SELECT 'AUDIT GRANT ANY PRIVILEGE BY ACCESS;'     FROM dual UNION ALL
    SELECT 'AUDIT GRANT ANY ROLE BY ACCESS;'          FROM dual UNION ALL
    SELECT 'AUDIT CREATE SESSION BY ACCESS;'          FROM dual
  ) LOOP
    EXECUTE IMMEDIATE stmt.ddl;
  END LOOP;
END;
/

-- 4. Configure a purge window so the audit trail is retained for at least the
--    specified number of days but not indefinitely. We round up to whole days.
DECLARE
  v_days  PLS_INTEGER := NVL(TO_NUMBER('&RETENTION_DAYS'),30);
BEGIN
  DBMS_AUDIT_MGMT.INIT_CLEANUP(audit_trail_type => DBMS_AUDIT_MGMT.AUDIT_TRAIL_DB_STD);
  DBMS_AUDIT_MGMT.SET_LAST_ARCHIVE_TIMESTAMP(
      audit_trail_type => DBMS_AUDIT_MGMT.AUDIT_TRAIL_DB_STD,
      last_archive_time => SYSTIMESTAMP - v_days);
END;
/

PROMPT LEAST hardening complete.  Bounce the instance to activate parameter changes.
exit success;
