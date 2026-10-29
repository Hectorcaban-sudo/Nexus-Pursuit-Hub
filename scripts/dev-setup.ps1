<#
.SYNOPSIS
    Nexus Pursuit Hub: install into a development org from this repo (PowerShell version of dev-setup.sh).

.DESCRIPTION
    Steps: org -> deploy all packages (API 68.0) -> env-config\dev -> permission sets -> sample data -> jobs.
    Remove again with scripts\uninstall.ps1.

.EXAMPLE
    .\scripts\dev-setup.ps1
    New scratch org "nxp-dev" (7 days).
.EXAMPLE
    .\scripts\dev-setup.ps1 -Alias my-dev -Days 14
.EXAMPLE
    .\scripts\dev-setup.ps1 -Org my-sandbox
    Use an existing sandbox instead of a scratch org.
.EXAMPLE
    .\scripts\dev-setup.ps1 -Org my-sandbox -NoSampleData
#>
[CmdletBinding()]
param(
    [string]$Alias = 'nxp-dev',
    [ValidateRange(1, 30)][int]$Days = 7,
    [string]$Org,
    [switch]$NoSampleData
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Set-Location $RepoRoot
Assert-SfCli

if ($Org) {
    $Alias = $Org
    Write-Step "Using existing org $Alias"
}
else {
    Write-Step "Creating scratch org $Alias ($Days days)"
    Invoke-Sf @('org', 'create', 'scratch', '--definition-file', 'config/project-scratch-def.json', '--alias', $Alias,
        '--duration-days', "$Days", '--set-default', '--wait', '20')
}

Write-Step 'Deploying packages in dependency order (one deployment)'
Invoke-Sf (@('project', 'deploy', 'start', '--source-dir') + $PackageDirs +
    @('--target-org', $Alias, '--api-version', $ApiVersion, '--wait', '30'))

Write-Step 'Deploying env-config/dev'
Push-Location (Join-Path $RepoRoot 'env-config\dev')
try {
    Invoke-Sf @('project', 'deploy', 'start', '--source-dir', 'force-app', '--target-org', $Alias, '--api-version', $ApiVersion, '--wait', '10')
}
finally {
    Pop-Location
}

Write-Step 'Assigning permission sets'
Invoke-Sf @('org', 'assign', 'permset', '--name', 'NXP_User', '--name', 'NXP_Power_User', '--name', 'NXP_Admin', '--target-org', $Alias)

if (-not $NoSampleData) {
    & (Join-Path $PSScriptRoot 'load-sample-data.ps1') -Org $Alias
}

Write-Step 'Scheduling background jobs'
Invoke-ApexFile 'scripts/post-deploy/schedule-jobs.apex' $Alias

Write-Host ''
Write-Host 'Done. Next:' -ForegroundColor Green
Write-Host '  1. Setup > Named Credentials > External Credentials > NXP SAM.gov > Principals > Default:'
Write-Host '     add an Authentication Parameter named ApiKey with your SAM.gov API key.'
Write-Host "  2. Test it:  .\scripts\test-functional.ps1 -Org $Alias"
Write-Host "  3. Open it:  sf org open --target-org $Alias --path /lightning/n/NXP_Match_Inbox"
