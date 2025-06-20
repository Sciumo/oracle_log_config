# Oracle Minimal STIG Logging Toolkit

Is your Oracle database generating a firehose of logs? Are audit files consuming all your disk space? Is performance suffering because of overly aggressive, out-of-the-box audit settings?

This toolkit is designed to solve that problem.

The goal is to help you achieve **Minimal Acceptable STIG Compliance**. We will help you turn off the unnecessary logging, configure exactly what the STIG requires, and provide the reports to prove it to your information assurance team. You just want your database to work, be compliant, and not fill up the server. This toolkit gets you there.

## The 3-Step Workflow

This project is designed around a simple, problem-solving journey:

| Step | Your Goal | The Tool You'll Use |
| :--- | :--- | :--- |
| **1. Diagnose** | "What is my current logging configuration, and why is it so verbose?" | `Get-OracleLoggingConfig` Wrappers |
| **2. Apply Fix** | "Apply a sane, STIG-compliant logging configuration to my database." | `apply_sql.sh` (or PowerShell equivalent) |
| **3. Prove** | "Generate a report to prove to my security team that we are compliant." | `audit_oracle_stig_logging.sh` |

## Understanding the Compliance Levels

This toolkit isn't one-size-fits-all. It offers two levels of configuration based on different interpretations of the STIG controls. Your Information Assurance (IA) officer will determine which level is appropriate for your deployment.

*   **`LEAST` Compliance:** This level represents a **minimalist interpretation** of the STIG controls. It configures the absolute bare minimum required to satisfy every logging and auditing requirement, resulting in the lowest possible resource overhead.
*   **`NOMINAL` Compliance:** This level represents a **more robust interpretation** of the STIG controls. It provides a more comprehensive audit trail by including additional recommended settings beyond the bare minimum.

## STIG Controls Covered in This Toolkit

The scripts concentrate on the DISA Oracle Database 19c STIG (Revision 4).
The table shows which findings are satisfied at each compliance tier.

| STIG ID      | Control (short description)                                                                                                                                                                                                     | LEAST | NOMINAL |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :---: | :-----: |
| **V-215627** | `AUDIT_TRAIL` must be **NONE** to force pure unified auditing. ([stigviewer.com][1])                                                                                                                                            |   ✔   |    ✔    |
| **V-215650** | Failed logon attempts must be audited. This is met by enabling the unified policy that audits `LOGON`/`LOGOFF`. ([docs.oracle.com][2])                                                                                          |   ✔   |    ✔    |
| **V-215648** | Audit data must be retained ≥ 1 year (or the `-D` days you pass) and purged by a managed job. The toolkit sets the last-archive timestamp and creates **PURGE\_UNIFIED\_AUDIT\_STIG** to run every 24 h. ([docs.oracle.com][3]) |   ✔   |    ✔    |
| **V-215646** | Use of system privileges (DBA-class activity) must be audited. Provided by the `STIG_NOM_SYS_PRIV_POL` unified policy. ([docs.oracle.com][2])                                                                                   |   —   |    ✔    |
| **V-215621** | `AUDIT_SYS_OPERATIONS` must be **TRUE** so all SYS actions are captured. The pre-restart script writes this to the SPFILE (or creates an SPFILE if absent) so it survives every reboot. ([docs.oracle.com][4])                  |   —   |    ✔    |

*LEAST* therefore meets the absolute minimum the STIG demands, while *NOMINAL* adds SYS auditing and full DBA-privilege coverage for environments that need a broader evidence trail.

---

## How Parameters Persist: SPFILE, PFILE, and the Restart

Oracle stores static instance parameters in either a **server parameter file (SPFILE)** or a plain-text **PFILE**.
`ALTER SYSTEM … SCOPE=SPFILE` updates the SPFILE immediately, but the change takes effect only if the next startup reads that file. If the instance still boots from a PFILE, SPFILE edits are silently ignored ([techtarget.com][5]).

The toolkit now handles this automatically:

1. **SPFILE present** – The pre-restart script writes

   ```sql
   ALTER SYSTEM SET audit_trail = NONE  SCOPE=SPFILE;
   ALTER SYSTEM SET audit_sys_operations = TRUE SCOPE=SPFILE;
   ```

   Both values persist and become active after the planned restart.

2. **PFILE in use** – The script detects the absence of an SPFILE and runs

   ```sql
   CREATE SPFILE FROM MEMORY;
   ```

   which snapshots the current in-memory settings (including the two changes) into a new SPFILE ([stigviewer.com][6]).
   The restart that follows boots from this SPFILE automatically, so the parameters are permanent without manual file editing.

After the reboot, the post-restart script:

* applies the unified-audit retention watermark (`DBMS_AUDIT_MGMT.SET_LAST_ARCHIVE_TIMESTAMP`),
* recreates the unified-only purge job, and
* prints a readiness snapshot that confirms legacy trails are either initialised or inactive.

This ensures that both LEAST and NOMINAL hardening survive power-cycles, switchover operations, and patching reboots without further intervention, while still allowing operators to revert by restoring the original parameter file if required.

[1]: https://stigviewer.com/stigs/oracle_database_12c/2021-04-06/finding/V-220274?utm_source=chatgpt.com "The DBMS must produce audit records containing ... - STIG VIEWER"
[2]: https://docs.oracle.com/en/database/oracle/oracle-database/21/dbseg/configuring-audit-policies.html?utm_source=chatgpt.com "26 Configuring Audit Policies - Oracle Help Center"
[3]: https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/administering-the-audit-trail.html?utm_source=chatgpt.com "28 Administering the Audit Trail - Oracle Help Center"
[4]: https://docs.oracle.com/en/database/oracle/oracle-database/21/refrn/AUDIT_SYS_OPERATIONS.html?utm_source=chatgpt.com "AUDIT_SYS_OPERATIONS - Oracle Help Center"
[5]: https://www.techtarget.com/searchsap/answer/What-is-the-difference-between-SPFILE-and-PFILE-in-Oracle?utm_source=chatgpt.com "What is the difference between SPFILE and PFILE in Oracle?"
[6]: https://stigviewer.com/stigs/oracle_database_12c/2024-12-06/finding/V-219868?utm_source=chatgpt.com "Changes to configuration options must be audited. - STIG VIEWER"


## The Important Part: A Planned Database Restart is Required

To stop the old, problematic logging mechanisms, we must change a core database parameter (`audit_trail`). This type of setting is "baked in" and only takes effect after a **database restart**.

This is a significant operational event. It must be planned and coordinated with your team.

Our scripts are designed around this reality. The hardening process is split into a two-phase workflow:
1.  **Pre-Restart:** Run the `_pre.sql` script for your chosen compliance level. This stages the required changes.
2.  **Post-Restart:** After your administrator has restarted the database, run the corresponding `_post.sql` script to complete the configuration.

---

### Workflow 1: How to See Your Current Logging Settings (Diagnose)

Before you change anything, see where you stand. This step uses a powerful core SQL script (`oracle_logging_audit.sql`) to do the heavy lifting. We provide thin wrappers for both PowerShell and Bash to make it easy to run.

#### **On Windows (using PowerShell):**
```powershell
# This command will generate a detailed text report of your current settings.
.\Get-OracleLoggingConfig.ps1 -Server "oradb.mycompany.com" -Service "PRODDB" -Username "system"
```

#### **On Linux/Unix (using Bash):**
```bash
# This command does the same thing as the PowerShell version.
./get_oracle_logging_config.sh -s oradb.mycompany.com -d PRODDB -u system
```

### What the Diagnostic Report Contains

Both wrappers generate a detailed text file (`oracle_logging_config_...txt`) that documents a comprehensive set of configurations. This is the contract for what these scripts will show you:

#### Audit Configuration
- Current audit trail settings and destinations
- Statement, privilege, and object-level audit options
- Unified auditing policies (12c+)
- Audit file sizes and locations

#### SQL Tracing Configuration
- SQL trace parameters (sql_trace, timed_statistics)
- Event tracing settings (10046, 10053, etc.)
- Active session trace settings
- Trace file locations and sizes

#### Alert Log and Diagnostics
- Alert log parameters and destinations
- ADR (Automatic Diagnostic Repository) configuration
- Diagnostic dump destinations
- Checkpoint logging settings

#### Archive Log Configuration
- Archive log parameters and destinations
- Archive log space usage and quotas
- Archive log generation rates

#### Redo Log Configuration
- Redo log group sizes and members
- Redo log switching frequency

#### Space Usage Analysis
- Archive log space consumption
- Trace file space usage
- Large trace files identification
- Growth rate analysis

This detailed information is critical for identifying exactly which audit settings, trace events, or log configurations are responsible for excessive disk usage and performance overhead.

---

### Workflow 2: How to Apply STIG-Compliant Logging (Apply Fix)

This is a manual, two-phase process that must be coordinated with your DBA team.

#### **Phase 1: Apply Pre-Restart Script**
Choose your compliance level and run the corresponding `_pre` script. This stages the changes but does **not** affect the running database.
```bash
# Example for applying the LEAST pre-restart configuration
./apply_sql.sh \
  -s oradb.mycompany.com \
  -d PRODDB \
  -u sys \
  --sql-file ./least_hardening_pre.sql \
  -D 30
```
**Action Required:** At this point, you must schedule a maintenance window and have a database administrator **restart the Oracle instance**.

#### **Phase 2: Apply Post-Restart Script**
After the database has been successfully restarted, run the corresponding `_post` script to finalize the configuration.
```bash
# Example for applying the LEAST post-restart configuration
./apply_sql.sh \
  -s oradb.mycompany.com \
  -d PRODDB \
  -u sys \
  --sql-file ./least_hardening_post.sql \
  -D 30
```
Your database is now hardened to your chosen compliance level.

---

### Workflow 3: How to Prove Compliance (Prove)

After you have applied a compliance level, run the audit script to generate a formal report for your security and information assurance teams. This script can be run from any machine with an Oracle Client.

```bash
# Run this from a client machine.
# Ensure you test for the compliance level you applied.
./audit_oracle_stig_logging.sh \
  -s oradb.mycompany.com \
  -d PRODDB \
  -u sysadmin \
  -c LEAST
```
This will produce two files:
*   `stig_audit_...txt`: A human-readable report stating whether the configuration is compliant.
*   `remediation_...sql`: An SQL script with the exact commands to fix any findings (this file is deleted if you are 100% compliant).

---

## For Developers: The Automated Test Suite

This project includes a fully automated test suite for validation and CI/CD purposes. **This is the only part of the project that requires Docker.**

The test suite requires a pre-built Oracle Docker image. A helper script is provided to build it.

1.  **Build the Test Image (One-time setup):**
    ```bash
    ./create_oracle_image.sh
    ```
2.  **Run the Test Suite:**
    ```bash
    ./test_oracle_logging.sh
    ```
The test script will automatically create a container from the image, apply the `LEAST` and `NOMINAL` configurations (including the restart), and run the audit script to verify the outcome at each stage.

## File Manifest & Their Roles

| Script Name | Role | Who Runs It & Where |
| :--- | :--- | :--- |
| **`apply_sql.sh`** | **The Worker.** A low-level utility that runs one `.sql` file. | **DBA** on a client machine |
| **`audit_oracle_stig_logging.sh`**| **The Auditor.** Checks an existing DB and generates a compliance report. | **DBA / Security Auditor** on a client machine |
| **`Get-OracleLoggingConfig.ps1`** <br/> **`get_oracle_logging_config.sh`** | **The Diagnosticians.** These are **self-contained scripts** for Windows and Linux. The comprehensive SQL query is embedded inside, so they can be run without other dependencies to generate a full report. | **DBA** on a Windows or Linux client |
| **`report.sql`** | **Standalone Reporting Engine.** This is the standalone version of the diagnostic query. It is **not** used by the `Get-Oracle...` wrappers, but is called directly by the `run_report_on_docker.sh` utility for developer convenience. | Called by `run_report_on_docker.sh` |
| **`run_report_on_docker.sh`** | **Developer Utility.** A simple script for developers to quickly generate a report from the test Docker container by calling `report.sql`. | **Developer** on their workstation |
| **`*_pre.sql` / `*_post.sql`** | **The Payloads.** The actual SQL commands that configure the database. | Called by `apply_sql.sh` |
| **`create_oracle_image.sh`** | **Test Environment Builder.** For developers. Builds the required Docker image. | **Developer** on their workstation |
| **`test_oracle_logging.sh`** | **The Test Suite.** For developers. Automates the full test cycle using Docker. | **Developer** on their workstation |
