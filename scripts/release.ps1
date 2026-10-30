<#
.SYNOPSIS
    Release Nexus Pursuit Hub to an environment with sf commands (PowerShell version of release.sh).

.DESCRIPTION
    -Mode source  (default) validate with RunLocalTests, then quick-deploy the package folders as metadata.
    -Mode package install the package versions listed in release\versions.json, in order.
    Then deploys env-config\<Environment> and schedules the background jobs.

.EXAMPLE
    .\scripts\release.ps1 -Environment uat -Org nxp-uat
.EXAMPLE
    .\scripts\release.ps1 -Environment prod -Org nxp-prod -Mode package
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][Alias('Env')][ValidateSet('dev', 'qa', 'uat', 'prod')][string]$Environment,
    [Parameter(Mandatory = $true)][string]$Org,
    [ValidateSet('source', 'package')][string]$Mode = 'source'
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Set-Location $RepoRoot
Assert-SfCli

if (-not (Test-Path (Join-Path $RepoRoot "env-config\$Environment"))) { throw "No env-config\$Environment" }

$version = 'untagged'
try {
    $described = & git describe --tags --always
    if ($LASTEXITCODE -eq 0 -and $described) { $version = "$described".Trim() }
}
catch {
    $version = 'untagged'
}

Write-Step "Releasing $version to $Org ($Environment, $Mode)"
Write-Host "Reminder: $Org must already be on the Salesforce release that supports API $ApiVersion."

if ($Mode -eq 'source') {
    New-Item -ItemType Directory -Force -Path 'manifest' | Out-Null
    Invoke-Sf (@('project', 'generate', 'manifest', '--source-dir') + $PackageDirs +
        @('--api-version', $ApiVersion, '--name', "release-$version", '--output-dir', 'manifest'))

    Write-Step 'Validating (RunLocalTests)'
    $validation = Invoke-SfJson (@('project', 'deploy', 'validate', '--source-dir') + $PackageDirs +
        @('--target-org', $Org, '--api-version', $ApiVersion, '--test-level', 'RunLocalTests', '--wait', '90'))
    if ($validation.status -ne 0 -or -not $validation.result.id) {
        $validation | ConvertTo-Json -Depth 8 | Write-Host
        throw "Validation failed: $($validation.message)"
    }
    $job = $validation.result.id
    Write-Host "Validation job: $job"
    $ok = Read-Host "Quick-deploy $job to $Org now? (yes/no)"
    if ($ok -ne 'yes') {
        Write-Host "Stopped. Quick-deploy later: sf project deploy quick --job-id $job --target-org $Org"
        return
    }
    Invoke-Sf @('project', 'deploy', 'quick', '--job-id', $job, '--target-org', $Org, '--wait', '60')
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    Add-Content -Path 'manifest/deployments.log' -Value "$version $Environment $Org $job $stamp"
}
else {
    $versionsFile = Join-Path $RepoRoot 'release\versions.json'
    if (-not (Test-Path $versionsFile)) { throw 'Create release\versions.json (see docs/deployment/deployment-guide.md)' }
    $versions = Get-Content -Raw $versionsFile | ConvertFrom-Json
    foreach ($pkg in $versions.install) {
        Write-Step "Installing $pkg"
        Invoke-Sf @('package', 'install', '--package', $pkg, '--target-org', $Org, '--wait', '30', '--no-prompt',
            '--security-type', 'AdminsOnly')
    }
}

Write-Step "env-config/$Environment"
Push-Location (Join-Path $RepoRoot "env-config\$Environment")
try {
    Invoke-Sf @('project', 'deploy', 'start', '--source-dir', 'force-app', '--target-org', $Org, '--api-version', $ApiVersion, '--wait', '15')
}
finally {
    Pop-Location
}

Write-Step 'Post-deploy'
Invoke-ApexFile 'scripts/post-deploy/schedule-jobs.apex' $Org

Write-Host ''
Write-Host 'Release finished. Complete docs/deployment/post-deployment-checklist.md:' -ForegroundColor Green
Write-Host '  credentials, permission sets, agent activation, smoke test (.\scripts\test-functional.ps1 in dev/QA).'
Write-Host '  First release in this org? Add the SAM.gov API key: Setup > Named Credentials > External Credentials >'
Write-Host '  NXP SAM.gov > Principals > Default > parameter ApiKey. Steps: docs/deployment/deployment-guide.md#samgov-api-key'
