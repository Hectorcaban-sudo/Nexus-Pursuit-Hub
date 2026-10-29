# Shared helpers for the PowerShell scripts in scripts\. Dot-sourced, not run:
#   . (Join-Path $PSScriptRoot 'lib\common.ps1')
# Works in Windows PowerShell 5.1 and PowerShell 7+. The bash scripts use scripts/lib/common.sh.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:ApiVersion = '68.0'
# Install order. Uninstall uses the reverse.
$script:PackageDirs = @(
    'packages/nxp-core',
    'packages/nxp-ingestion',
    'packages/nxp-search',
    'packages/nxp-push',
    'packages/nxp-experience',
    'packages/nxp-agents'
)

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-SfCli {
    if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
        throw 'Salesforce CLI (sf) not found. Install it: npm install --global @salesforce/cli'
    }
}

# Runs a command-line program (sf, npx, npm) and throws if it fails. Pass arguments as a flat array.
function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe $(@($Arguments)[0..1] -join ' ') failed (exit code $LASTEXITCODE). See the output above."
    }
}

# Runs sf and throws if it fails:  Invoke-Sf @('project', 'deploy', 'start', '--target-org', $Org)
function Invoke-Sf([string[]]$Arguments) {
    Invoke-Checked 'sf' $Arguments
}

# Runs sf with --json and returns the parsed object (also when the command failed; check .status).
function Invoke-SfJson([string[]]$Arguments) {
    $all = @($Arguments) + '--json'
    $raw = & sf @all | Out-String
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "sf $($Arguments[0..1] -join ' ') returned no output (exit code $LASTEXITCODE)."
    }
    return $raw | ConvertFrom-Json
}

# The System.debug lines from an anonymous Apex debug log.
function Get-DebugLines([string]$Log) {
    foreach ($line in ($Log -split "`r?`n")) {
        if ($line -match '\|USER_DEBUG\|\[\d+\]\|[A-Z]+\|(.*)$') {
            $Matches[1]
        }
    }
}

# Runs an anonymous Apex file and prints its System.debug lines. With -PassThru it prints nothing and
# returns the debug log instead.
function Invoke-ApexFile([string]$File, [string]$Org, [switch]$PassThru) {
    $result = Invoke-SfJson @('apex', 'run', '--file', $File, '--target-org', $Org)
    $r = $result.result
    if ($result.status -ne 0 -or $null -eq $r -or -not $r.success) {
        $why = $result.message
        if ($null -ne $r) {
            if (-not $r.compiled) { $why = "Compile error at line $($r.line): $($r.compileProblem)" }
            elseif (-not $r.success) { $why = "$($r.exceptionMessage)`n$($r.exceptionStackTrace)" }
        }
        throw "Anonymous Apex failed: $File`n$why"
    }
    if ($PassThru) {
        return $r.logs
    }
    Get-DebugLines $r.logs | ForEach-Object { Write-Host "   $_" }
}

# True for a production org (not a sandbox, not a scratch or trial org).
function Test-ProductionOrg([string]$Org) {
    $q = Invoke-SfJson @('data', 'query', '--query', 'SELECT IsSandbox, TrialExpirationDate FROM Organization', '--target-org', $Org)
    if ($q.status -ne 0) { throw "Could not query org $Org : $($q.message)" }
    $o = $q.result.records[0]
    return (-not $o.IsSandbox) -and ($null -eq $o.TrialExpirationDate)
}
