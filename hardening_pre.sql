-- hardening_pre.sql ── Phase-1 of the NOMINAL STIG hardening workflow
--
-- PURPOSE
--   • Persist audit_trail = NONE   and audit_sys_operations = TRUE in the SPFILE.
--   • If the instance is still using a PFILE, create an SPFILE from memory
--     so the settings survive the upcoming restart.
--   • Create / refresh unified-audit policies for NOMINAL compliance.
--
-- INVOCATION
--   @hardening_pre.sql <RETENTION_DAYS>
--
-- NOTE
--   This script writes to the SPFILE and exits.  Restart the database
--   and then run hardening_post.sql.

whenever sqlerror exit failure rollback;
set serveroutput on size unlimited;

prompt ==== PHASE-1 PRE-RESTART HARDENING ====

-------------------------------------------------------------------------------
-- 0.  Retention-days placeholder (kept for interface consistency)
-------------------------------------------------------------------------------
column ret_days new_value RET_DAYS noprint;
select case when regexp_like('&1','^\d+$') and to_number('&1') > 0
       then to_number('&1') else 30 end as ret_days
from dual;
prompt Retention days will be &RET_DAYS days.

-------------------------------------------------------------------------------
-- 1.  Persist parameters and ensure an SPFILE exists
-------------------------------------------------------------------------------
declare
    has_spfile number;  -- 1 = SPFILE in use, 0 = PFILE
begin
    select count(*) into has_spfile
    from   v$parameter
    where  name = 'spfile'
      and  value is not null;

    execute immediate
      q'[alter system set audit_trail          = NONE  scope=spfile]';
    execute immediate
      q'[alter system set audit_sys_operations = TRUE scope=spfile]';

    if has_spfile = 0 then
        dbms_output.put_line(
          'No SPFILE detected – creating spfile from memory so changes persist.');
        execute immediate 'create spfile from memory';
    else
        dbms_output.put_line('Parameters written to existing SPFILE.');
    end if;
end;
/

-------------------------------------------------------------------------------
-- 2.  Create / refresh unified-audit policies (NOMINAL superset)
-------------------------------------------------------------------------------
declare
    procedure ensure_policy(p_sql varchar2, p_name varchar2) is
        n number;
    begin
        select count(*) into n
        from   audit_unified_policies
        where  policy_name = p_name;
        if n = 0 then
            dbms_output.put_line('Creating policy '||p_name||' …');
            execute immediate p_sql;
        else
            dbms_output.put_line('Policy '||p_name||' already exists.');
        end if;
        execute immediate 'audit policy '||p_name;
    end;
begin
    ensure_policy(
        'create audit policy stig_nom_sys_priv_pol privileges all',
        'STIG_NOM_SYS_PRIV_POL');

    ensure_policy(
        q'[create audit policy stig_nom_dml_pol actions
             create table, drop table, truncate table,
             create procedure, drop procedure,
             grant, revoke]',
        'STIG_NOM_DML_POL');

    ensure_policy(
        'create audit policy stig_least_logon_pol actions logon, logoff',
        'STIG_LEAST_LOGON_POL');

    ensure_policy(
        'create audit policy stig_least_admin_pol actions
             create user, alter user, drop user,
             create role, alter role, drop role, set role,
             grant, revoke,
             alter system, alter database,
             audit, noaudit',
        'STIG_LEAST_ADMIN_POL');

    ensure_policy(
        'create audit policy stig_least_sys_actions_pol actions all',
        'STIG_LEAST_SYS_ACTIONS_POL');

    dbms_output.put_line('Unified audit policies staged and enabled.');
end;
/

prompt === Pre-restart staging complete.  Bounce the database, then run hardening_post.sql. ===
exit success;
