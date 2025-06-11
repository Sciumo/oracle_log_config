# Oracle Logging Configuration Audit Scripts

This collection of scripts documents comprehensive Oracle database logging, auditing, and tracing configurations to help identify what's consuming disk space and how to optimize logging settings.

## Scripts Included

1. **oracle_logging_audit.sql** - Core SQL script that queries all logging-related configurations
2. **Get-OracleLoggingConfig.ps1** - PowerShell wrapper for Windows environments
3. **get_oracle_logging_config.sh** - Bash wrapper for Linux/Unix environments

## What the Scripts Document

### Audit Configuration
- Current audit trail settings and destinations
- Statement, privilege, and object-level audit options
- Unified auditing policies (12c+)
- Audit file sizes and locations

### SQL Tracing Configuration
- SQL trace parameters (sql_trace, timed_statistics)
- Event tracing settings (10046, 10053, etc.)
- Active session trace settings
- Trace file locations and sizes

### Alert Log and Diagnostics
- Alert log parameters and destinations
- ADR (Automatic Diagnostic Repository) configuration
- Diagnostic dump destinations
- Checkpoint logging settings

### Archive Log Configuration
- Archive log parameters and destinations
- Archive log space usage and quotas
- Archive log generation rates

### Redo Log Configuration
- Redo log group sizes and members
- Redo log switching frequency

### Space Usage Analysis
- Archive log space consumption
- Trace file space usage
- Large trace files identification
- Growth rate analysis

## Usage

### PowerShell (Windows)

```powershell
# Basic usage
.\Get-OracleLoggingConfig.ps1 -Server "oradb01" -Service "PROD" -Username "system"

# With all parameters
.\Get-OracleLoggingConfig.ps1 -Server "oradb01" -Service "PROD" -Username "system" -Password "password" -Port "1521" -OutputDir "C:\temp\oracle_audit"

# Using custom SQL*Plus path
.\Get-OracleLoggingConfig.ps1 -Server "oradb01" -Service "PROD" -Username "system" -SqlPlusPath "C:\oracle\client\bin\sqlplus.exe"
```

### Bash (Linux/Unix)

```bash
# Basic usage (will prompt for password)
./get_oracle_logging_config.sh -s oradb01 -d PROD -u system

# With all parameters
./get_oracle_logging_config.sh -s oradb01 -d PROD -u system -p password -P 1521 -o /tmp/oracle_audit

# Using custom SQL*Plus path
./get_oracle_logging_config.sh -s oradb01 -d PROD -u system -x /opt/oracle/client/bin/sqlplus
```

### Direct SQL Execution

```sql
-- Connect to your database and run:
@oracle_logging_audit.sql
```

## Prerequisites

1. **Oracle Client** with SQL*Plus installed
2. **Database privileges**: User needs access to:
   - `v$parameter`, `v$session`, `v$instance`, `v$database`
   - `dba_stmt_audit_opts`, `dba_priv_audit_opts`, `dba_obj_audit_opts`
   - `v$diag_trace_file`, `v$diag_info`
   - `v$archive_dest`, `v$log`, `v$logfile`
   - `audit_unified_enabled_policies` (12c+)

## Output Files

The scripts generate several files:

- **oracle_logging_config_YYYYMMDD_HHMMSS.txt** - Main report with all configuration details
- **oracle_audit_YYYYMMDD_HHMMSS.log** - Execution log and any errors
- **Temporary SQL file** (cleaned up automatically)

## Key Sections in the Report

### 1. Database Information
Basic database identification and status

### 2. Audit Configuration
- **Current Audit Parameters**: Shows audit_trail, audit_file_dest, etc.
- **Statement Audit Options**: What SQL statements are being audited
- **Privilege Audit Options**: What system privileges are being audited
- **Object Audit Options**: What database objects have auditing enabled

### 3. SQL Tracing Configuration
- **SQL Trace Parameters**: Current trace settings
- **Event Parameters**: Special Oracle event tracing
- **Active Trace Files**: Recent trace files and their sizes

### 4. Space Usage Summary
- **Archive Log Space**: Current usage and limits
- **Large Trace Files**: Files consuming significant space
- **Growth Rates**: Recent logging activity levels

## Common Issues and Solutions

### High Disk Usage from Auditing
- Review "Statement Audit Options" section
- Use `NOAUDIT` commands to disable unnecessary auditing
- Implement audit trail cleanup procedures

### Large Trace Files
- Check "Large Trace Files" section
- Disable unnecessary SQL tracing
- Set appropriate `MAX_DUMP_FILE_SIZE` limits

### Archive Log Space Issues
- Review "Archive Log Configuration" section
- Implement proper backup and archive log deletion
- Adjust `DB_RECOVERY_FILE_DEST_SIZE` if needed

## Recommended Actions Based on Report

1. **Review Active Auditing**: Look for overly broad audit settings
2. **Check Trace Settings**: Ensure SQL tracing isn't enabled unnecessarily
3. **Monitor Growth Rates**: Use the archive log generation data to predict future space needs
4. **Cleanup Large Files**: Address any trace files >10MB identified in the report
5. **Optimize Parameters**: Adjust logging levels based on actual requirements

## Security Notes

- Scripts will prompt for passwords if not provided
- Passwords are not logged or stored
- Output files contain configuration data but no sensitive information
- Ensure output files are stored securely as they reveal database configuration

## Troubleshooting

### SQL*Plus Not Found
- Ensure Oracle Client is installed
- Add Oracle Client bin directory to PATH
- Use `-SqlPlusPath` (PowerShell) or `-x` (Bash) to specify custom path

### Permission Errors
- Ensure database user has necessary system privileges
- Grant SELECT privileges on required system views
- Consider using SYSDBA for comprehensive audit

### Connection Issues
- Verify TNS configuration
- Check network connectivity to database server
- Ensure service name is correct

## Customization

The SQL script can be modified to:
- Add additional parameters or views
- Filter results for specific schemas
- Include custom recommendations
- Export specific sections only

## Best Practices

1. **Run regularly** to monitor configuration changes
2. **Compare reports** over time to identify trends
3. **Document changes** when modifying logging settings
4. **Test in non-production** before implementing changes
5. **Coordinate with backup procedures** when changing archive log settings
