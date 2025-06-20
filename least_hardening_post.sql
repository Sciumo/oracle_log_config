/*  least_hardening_post.sql  ── TRUE-LEAST STIG hardening, post-restart

     PURPOSE
       • Verify the three minimum unified auditing policies required by the
         DISA STIG for Oracle 19c.
       • Show whether every legacy audit trail (DB, FGA, OS, XML) is initialised
         for cleanup and when it was last archived, without ever touching the
         unified trail routines that reject AUDIT_TRAIL_UNIFIED.
       • Schedule a purge job that deletes only unified-audit partitions older
         than &RET_DAYS (default 365) so the STIG “keep one year” rule is met.

     INVOCATION
         @least_hardening_post.sql <RETENTION_DAYS>
         Requires AUDIT_ADMIN and AUDIT_VIEWER or SYSDBA.

     WHY ORA-46250 DISAPPEARS
         ORA-46250 appears when AUDIT_TRAIL_UNIFIED is sent to INIT_CLEANUP or
         IS_CLEANUP_INITIALIZED.  Those calls are gone; unified status is
         reported directly.  All other constants are still checked.
*/

whenever sqlerror exit failure rollback;
set serveroutput on size unlimited;

/* Accept &RET_DAYS with a safe default of 365 */
column ret_days new_value RET_DAYS noprint;
select case
         when regexp_like('&1','^\d+$') and to_number('&1') > 0
         then to_number('&1')
         else 365
       end as ret_days
from   dual;
prompt Retention days set to &RET_DAYS
prompt --- Applying TRUE-LEAST compliance (post-restart) ---

/* 1. Make sure the unified-audit policies exist and are enabled */
declare
  procedure ensure_policy(p_sql varchar2, p_name varchar2) is
    n number;
  begin
    select count(*) into n from audit_unified_policies
    where policy_name = p_name;
    if n = 0 then
      dbms_output.put_line('Creating policy '||p_name||' …');
      execute immediate p_sql;
    else
      dbms_output.put_line('Policy '||p_name||' already exists.');
    end if;
    execute immediate 'audit policy '||p_name;
  end;
begin
  ensure_policy('create audit policy stig_least_logon_pol actions logon, logoff',
                'STIG_LEAST_LOGON_POL');

  ensure_policy(q'[create audit policy stig_least_admin_pol actions
                     create user, alter user, drop user,
                     create role, alter role, drop role, set role,
                     grant, revoke,
                     alter system, alter database,
                     audit, noaudit]',
                'STIG_LEAST_ADMIN_POL');

  ensure_policy('create audit policy stig_least_sys_actions_pol actions all',
                'STIG_LEAST_SYS_ACTIONS_POL');
  execute immediate
      'audit policy stig_least_sys_actions_pol by sys, system';

  dbms_output.put_line('Unified policies verified.');
end;
/

/* 2. Report readiness of every non-unified audit trail.
      IS_CLEANUP_INITIALIZED deliberately rejects AUDIT_TRAIL_UNIFIED, so that
      constant is skipped and its readiness is stated directly. */
declare
  type t_rec is record(id pls_integer, label varchar2(16));
  type t_tab is table of t_rec;
  trails t_tab := t_tab(
    t_rec(DBMS_AUDIT_MGMT.AUDIT_TRAIL_DB_STD,  'DB_STD'),
    t_rec(DBMS_AUDIT_MGMT.AUDIT_TRAIL_FGA_STD, 'FGA_STD'),
    t_rec(DBMS_AUDIT_MGMT.AUDIT_TRAIL_AUD_STD, 'AUD_STD'),
    t_rec(DBMS_AUDIT_MGMT.AUDIT_TRAIL_XML,     'XML'),
    t_rec(DBMS_AUDIT_MGMT.AUDIT_TRAIL_OS,      'OS'),
    t_rec(DBMS_AUDIT_MGMT.AUDIT_TRAIL_FILES,   'FILES')
  );
  v_ts timestamp;
begin
  dbms_output.put_line(chr(10)||'--- Audit-trail readiness snapshot ---');
  dbms_output.put_line('UNIFIED    always cleanup-ready by design');
  for i in 1 .. trails.count loop
    if DBMS_AUDIT_MGMT.IS_CLEANUP_INITIALIZED(trails(i).id) then
      begin
        v_ts := DBMS_AUDIT_MGMT.GET_LAST_ARCHIVE_TIMESTAMP(trails(i).id);
      exception
        when others then v_ts := null;
      end;
      dbms_output.put_line(
        rpad(trails(i).label,10)||' initialised; last archive '||
        coalesce(to_char(v_ts,'YYYY-MM-DD HH24:MI:SS'),'not set'));
    else
      dbms_output.put_line(rpad(trails(i).label,10)||' NOT initialised');
    end if;
  end loop;
exception
  when others then
    /* Catch any surprise 46250 for a new constant not yet supported */
    if sqlcode = -46250 then
      dbms_output.put_line('Skipped unsupported audit-trail type (SQLCODE -46250).');
    else
      raise;
    end if;
end;
/

/* 3. Unified-only purge job */
declare
  v_days pls_integer := &RET_DAYS;
begin
  dbms_output.put_line(chr(10)||'Configuring unified-audit purge job ...');

  DBMS_AUDIT_MGMT.SET_LAST_ARCHIVE_TIMESTAMP(
    audit_trail_type  => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
    last_archive_time => systimestamp - v_days);

  begin
    DBMS_AUDIT_MGMT.DROP_PURGE_JOB(
      audit_trail_purge_name => 'PURGE_AUDIT_TRAIL_STIG');
  exception
    when others then
      if sqlcode in (-46262, -46255) then null; else raise; end if;
  end;

  DBMS_AUDIT_MGMT.CREATE_PURGE_JOB(
    audit_trail_type           => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
    audit_trail_purge_interval => 24,
    audit_trail_purge_name     => 'PURGE_AUDIT_TRAIL_STIG',
    use_last_arch_timestamp    => true);

  dbms_output.put_line('Unified-audit purge job scheduled.');
end;
/

exit success;
