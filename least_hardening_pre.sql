-- least_hardening_pre.sql -- Sets the parameters for LEAST compliance.
--
-- PURPOSE:
-- Sets the static parameter `audit_trail=NONE` which is the mandatory
-- first step for enabling Pure Unified Auditing.
--
-- INVOCATION:
-- A database restart is REQUIRED after running this script.
--
whenever sqlerror exit failure rollback;
SET SERVEROUTPUT ON;

PROMPT --- Applying LEAST compliance (Pre-Restart) ---

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
    DBMS_OUTPUT.PUT_LINE('Set audit_trail=NONE in SPFILE. A restart is now required.');
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET audit_trail = NONE SCOPE=SPFILE';
  ELSE
    DBMS_OUTPUT.PUT_LINE('OK: audit_trail is correctly set to NONE.');
  END IF;

END;
/

exit success;