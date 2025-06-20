-- hardening_post.sql ── Phase-2 of NOMINAL STIG hardening  (run *after* restart)
--
-- PURPOSE
--   • Apply the unified-audit retention watermark (&RET_DAYS days).
--   • Ensure a 24-hour purge job exists for the unified audit trail only.
--   • Display a cleanup-readiness snapshot of legacy audit trails.
--
-- INVOCATION
--     @hardening_post.sql <RETENTION_DAYS>   (defaults to 365)
--
-- ROLES
--     SYS or a user with AUDIT_ADMIN and AUDIT_VIEWER.

whenever sqlerror exit failure rollback;
set serveroutput on size unlimited;

-------------------------------------------------------------------------------
-- Resolve &RET_DAYS (default 365)
-------------------------------------------------------------------------------
column ret_days new_value RET_DAYS noprint;
select case
         when regexp_like('&1','^\d+$') and to_number('&1') > 0
         then to_number('&1') else 365
       end as ret_days
from dual;

prompt Retention days set to &RET_DAYS
prompt --- Finishing NOMINAL hardening (post-restart) ---

-------------------------------------------------------------------------------
-- Disable & substitution inside the anonymous block
-------------------------------------------------------------------------------
set define off;

DECLARE
    /* ---------- shared data ---------------------------------------------- */
    v_days constant pls_integer := &RET_DAYS;

    /* Convert BOOLEAN to YES/NO for snapshot lines */
    function yesno(b boolean) return varchar2 is
    begin
        return case when b then 'YES' else 'NO' end;
    end;

    /* ---------- retention watermark -------------------------------------- */
    procedure set_retention_ts is
    begin
        dbms_audit_mgmt.set_last_archive_timestamp(
            audit_trail_type   => dbms_audit_mgmt.audit_trail_unified,
            last_archive_time  => systimestamp - v_days);
        dbms_output.put_line(
            'Unified trail watermark set to '
          || to_char(systimestamp - v_days,'YYYY-MM-DD HH24:MI:SS'));
    end;

    /* ---------- purge-job management ------------------------------------- */
    procedure recreate_purge_job is
    begin
        /* drop old job if it exists */
        begin
            dbms_audit_mgmt.drop_purge_job(
              audit_trail_purge_name => 'PURGE_UNIFIED_AUDIT_STIG');
        exception
            when others then
                if sqlcode not in (-46262, -46255) then raise; end if;
        end;

        /* create fresh 24-hour job */
        dbms_audit_mgmt.create_purge_job(
            audit_trail_type           => dbms_audit_mgmt.audit_trail_unified,
            audit_trail_purge_name     => 'PURGE_UNIFIED_AUDIT_STIG',
            audit_trail_purge_interval => 24,
            use_last_arch_timestamp    => true);

        dbms_output.put_line('Unified-audit purge job scheduled (24 h interval).');
    end;

    /* ---------- legacy-trail snapshot ------------------------------------ */
    procedure snapshot is
        type t_rec is record(id pls_integer, label varchar2(16));
        type t_tab is table  of t_rec;
        trails t_tab := t_tab(
            t_rec(dbms_audit_mgmt.audit_trail_db_std,  'DB_STD'),
            t_rec(dbms_audit_mgmt.audit_trail_fga_std, 'FGA_STD'),
            t_rec(dbms_audit_mgmt.audit_trail_aud_std, 'AUD_STD'),
            t_rec(dbms_audit_mgmt.audit_trail_xml,     'XML'),
            t_rec(dbms_audit_mgmt.audit_trail_os,      'OS'),
            t_rec(dbms_audit_mgmt.audit_trail_files,   'FILES')
        );
        init boolean; v_ts timestamp;
    begin
        dbms_output.put_line(chr(10)||'--- Audit-trail readiness snapshot ---');
        dbms_output.put_line('UNIFIED initialised : YES');
        for i in 1 .. trails.count loop
            init := dbms_audit_mgmt.is_cleanup_initialized(trails(i).id);
            if init then
                v_ts := dbms_audit_mgmt.get_last_archive_timestamp(trails(i).id);
            else
                v_ts := null;
            end if;
            dbms_output.put_line(
                rpad(trails(i).label,5)||' initialised : '
              || yesno(init)||'; last archive '
              || coalesce(to_char(v_ts,'YYYY-MM-DD HH24:MI:SS'),'n/a'));
        end loop;
    end;

BEGIN
    set_retention_ts;
    recreate_purge_job;
    snapshot;
EXCEPTION
    when others then
        dbms_output.put_line('Fatal error: '||sqlerrm);
        raise;
END;
/

-------------------------------------------------------------------------------
-- Restore default substitution behaviour
-------------------------------------------------------------------------------
set define on;

exit success;
