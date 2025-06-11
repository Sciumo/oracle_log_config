# Oracle Logging Configuration Documentation - PowerShell Script
# Usage: .\Get-OracleLoggingConfig.ps1 -Server "hostname" -Service "ORCL" -Username "system" [-Password "password"]

param(
    [Parameter(Mandatory=$true)]
    [string]$Server,
    
    [Parameter(Mandatory=$true)]
    [string]$Service,
    
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$Port = "1521",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputDir = ".",
    
    [Parameter(Mandatory=$false)]
    [string]$SqlPlusPath = "sqlplus"
)

# Function to write colored output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

# Function to check if SQL*Plus is available
function Test-SqlPlus {
    try {
        $null = & $SqlPlusPath -v 2>&1
        return $true
    }
    catch {
        return $false
    }
}

Write-ColorOutput Green "Oracle Logging Configuration Documentation Script"
Write-ColorOutput Green "=================================================="

# Check if SQL*Plus is available
if (-not (Test-SqlPlus)) {
    Write-ColorOutput Red "ERROR: SQL*Plus not found at path: $SqlPlusPath"
    Write-ColorOutput Yellow "Please ensure Oracle Client is installed and SQL*Plus is in PATH, or specify -SqlPlusPath parameter"
    exit 1
}

# Get password if not provided
if (-not $Password) {
    $SecurePassword = Read-Host "Enter password for $Username" -AsSecureString
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))
}

# Create timestamp for file naming
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$sqlFile = Join-Path $OutputDir "oracle_logging_audit.sql"
$outputFile = Join-Path $OutputDir "oracle_logging_config_$timestamp.txt"
$logFile = Join-Path $OutputDir "oracle_audit_$timestamp.log"

Write-ColorOutput Cyan "Configuration:"
Write-Output "  Server: $Server"
Write-Output "  Port: $Port"
Write-Output "  Service: $Service"
Write-Output "  Username: $Username"
Write-Output "  Output Directory: $OutputDir"
Write-Output "  SQL File: $sqlFile"
Write-Output "  Output File: $outputFile"

# Create the SQL script content
$sqlContent = @"
-- Oracle Logging, Audit, and Trace Configuration Documentation
-- Generated on: $timestamp
-- Database: ${Server}:${Port}/${Service}

SET PAGESIZE 1000
SET LINESIZE 200
SET TRIMSPOOL ON
SET ECHO OFF
SET FEEDBACK OFF
SET HEADING ON

SPOOL $outputFile

PROMPT ===============================================
PROMPT ORACLE DATABASE LOGGING CONFIGURATION REPORT
PROMPT ===============================================
PROMPT
PROMPT Database Information:
SELECT instance_name, host_name, version, startup_time, database_status 
FROM v`$instance;

PROMPT
PROMPT Database Name and ID:
SELECT name as db_name, dbid, log_mode, open_mode 
FROM v`$database;

PROMPT
PROMPT ===============================================
PROMPT AUDIT CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Current Audit Parameters:
SELECT name, value, description 
FROM v`$parameter 
WHERE name LIKE '%audit%' 
ORDER BY name;

PROMPT
PROMPT Statement Audit Options (What statements are being audited):
SELECT user_name, audit_option, success, failure 
FROM dba_stmt_audit_opts 
ORDER BY user_name, audit_option;

PROMPT
PROMPT Privilege Audit Options:
SELECT user_name, privilege, success, failure 
FROM dba_priv_audit_opts 
ORDER BY user_name, privilege;

PROMPT
PROMPT Object Audit Options:
SELECT owner, object_name, object_type, alt, aud, com, del, gra, ind, ins, loc, ren, sel, upd, ref, exe, cre, rea, wri, fbk
FROM dba_obj_audit_opts 
WHERE alt != '-/-' OR aud != '-/-' OR com != '-/-' OR del != '-/-' 
   OR gra != '-/-' OR ind != '-/-' OR ins != '-/-' OR loc != '-/-'
   OR ren != '-/-' OR sel != '-/-' OR upd != '-/-' OR ref != '-/-'
   OR exe != '-/-' OR cre != '-/-' OR rea != '-/-' OR wri != '-/-' OR fbk != '-/-'
ORDER BY owner, object_name;

PROMPT
PROMPT Unified Auditing Policies (12c+):
SELECT policy_name, enabled_option, entity_name, entity_type, success, failure
FROM audit_unified_enabled_policies
ORDER BY policy_name, entity_name;

PROMPT
PROMPT ===============================================
PROMPT SQL TRACING CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT SQL Trace and Timing Parameters:
SELECT name, value, description 
FROM v`$parameter 
WHERE name IN ('sql_trace', 'timed_statistics', 'max_dump_file_size', 
               'user_dump_dest', 'background_dump_dest', 'diagnostic_dest',
               'sql_trace_waits', 'sql_trace_binds')
ORDER BY name;

PROMPT
PROMPT Event Parameters (10046, 10053, etc.):
SELECT name, value 
FROM v`$parameter 
WHERE name LIKE '%event%' AND value IS NOT NULL;

PROMPT
PROMPT Current Session Trace Settings:
SELECT s.sid, s.serial#, s.username, s.sql_trace, s.sql_trace_waits, s.sql_trace_binds,
       s.program, s.machine
FROM v`$session s 
WHERE s.username IS NOT NULL
ORDER BY s.username, s.sid;

PROMPT
PROMPT Active Trace Files:
SELECT trace_filename, change_time, sizeblks*block_size/1024 as size_kb
FROM v`$diag_trace_file 
WHERE trace_filename LIKE '%.trc'
  AND change_time > SYSDATE - 1
ORDER BY change_time DESC;

PROMPT
PROMPT ===============================================
PROMPT ALERT LOG AND DIAGNOSTIC CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Alert Log and Diagnostic Parameters:
SELECT name, value, description 
FROM v`$parameter 
WHERE name LIKE '%log%' AND name LIKE '%alert%'
   OR name LIKE '%diagnostic%'
   OR name LIKE '%dump%'
   OR name IN ('log_checkpoints_to_alert', 'log_archive_trace')
ORDER BY name;

PROMPT
PROMPT ADR (Automatic Diagnostic Repository) Information:
SELECT inst_id, comp_id, adr_home, adr_base, banner 
FROM v`$diag_info;

PROMPT
PROMPT ===============================================
PROMPT ARCHIVE LOG CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Archive Log Parameters:
SELECT name, value 
FROM v`$parameter 
WHERE name LIKE '%archive%' OR name LIKE '%log_archive%'
ORDER BY name;

PROMPT
PROMPT Archive Log Destinations:
SELECT dest_id, status, destination, target, schedule, process, delay_mins,
       quota_size, quota_used
FROM v`$archive_dest 
WHERE status != 'INACTIVE';

PROMPT
PROMPT ===============================================
PROMPT REDO LOG CONFIGURATION
PROMPT ===============================================

PROMPT
PROMPT Redo Log Groups and Sizes:
SELECT l.group#, l.thread#, l.sequence#, l.bytes/1024/1024 as size_mb, 
       l.blocksize, l.members, l.status
FROM v`$log l
ORDER BY l.group#;

PROMPT
PROMPT ===============================================
PROMPT SPACE USAGE SUMMARY
PROMPT ===============================================

PROMPT
PROMPT Archive Log Space Usage:
SELECT dest_name, space_limit/1024/1024/1024 as limit_gb, 
       space_used/1024/1024/1024 as used_gb,
       round(space_used/space_limit*100,2) as pct_used
FROM v`$recovery_file_dest;

PROMPT
PROMPT Large Trace Files (>10MB):
SELECT trace_filename, sizeblks*block_size/1024/1024 as size_mb, change_time
FROM v`$diag_trace_file 
WHERE sizeblks*block_size > 10*1024*1024
ORDER BY sizeblks DESC;

PROMPT
PROMPT Report completed at: 
SELECT to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS') as report_time FROM dual;

SPOOL OFF
SET FEEDBACK ON
SET ECHO ON
EXIT;
"@

# Write SQL content to file
try {
    $sqlContent | Out-File -FilePath $sqlFile -Encoding UTF8
    Write-ColorOutput Green "SQL script created: $sqlFile"
}
catch {
    Write-ColorOutput Red "ERROR: Could not create SQL file: $_"
    exit 1
}

# Construct connection string
$connectionString = "${Username}/${Password}@${Server}:${Port}/${Service}"

Write-ColorOutput Cyan "`nExecuting Oracle audit script..."
Write-Output "Start time: $(Get-Date)"

try {
    # Execute SQL*Plus
    $process = Start-Process -FilePath $SqlPlusPath -ArgumentList "-S", $connectionString, "@$sqlFile" -Wait -NoNewWindow -PassThru -RedirectStandardOutput $logFile -RedirectStandardError $logFile
    
    if ($process.ExitCode -eq 0) {
        Write-ColorOutput Green "`nScript executed successfully!"
        Write-Output "Output file: $outputFile"
        Write-Output "Log file: $logFile"
        
        # Show file sizes
        if (Test-Path $outputFile) {
            $size = (Get-Item $outputFile).Length
            Write-Output "Output file size: $([math]::Round($size/1KB, 2)) KB"
        }
        
        if (Test-Path $logFile) {
            $logSize = (Get-Item $logFile).Length
            Write-Output "Log file size: $([math]::Round($logSize/1KB, 2)) KB"
        }
    }
    else {
        Write-ColorOutput Red "ERROR: SQL*Plus exited with code $($process.ExitCode)"
        if (Test-Path $logFile) {
            Write-ColorOutput Yellow "Check log file for details: $logFile"
            Write-Output "`nLast few lines of log:"
            Get-Content $logFile | Select-Object -Last 10
        }
    }
}
catch {
    Write-ColorOutput Red "ERROR: Failed to execute SQL*Plus: $_"
    exit 1
}

Write-Output "`nEnd time: $(Get-Date)"

# Cleanup
if (Test-Path $sqlFile) {
    Remove-Item $sqlFile
}

Write-ColorOutput Green "`nOracle logging configuration audit completed!"
if (Test-Path $outputFile) {
    Write-ColorOutput Yellow "To view the report: Get-Content '$outputFile' | More"
}