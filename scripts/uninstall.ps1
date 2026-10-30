<#
.SYNOPSIS
    Remove Nexus Pursuit Hub from an org. Everything NXP_ goes, including all Nexus records.

.DESCRIPTION
    1. Stops the NXP scheduled and queued jobs and removes the NXP permission set assignments.
    2. -Mode source  (default, for orgs deployed with sf commands): deletes the components of each
       package folder with a destructive deployment, dependents first (agents ... core).
       -Mode package (for orgs with the unlocked packages installed): uninstalls the seven packages,
       dependents first.
    Before you run it, delete what was built by hand: the Nexus Pursuit Assistant agent and its NXP
    agent actions, the NXP prompt templates, and reports, flows or list views built on NXP objects.
    Opportunity records created by pushes are kept.
    Scratch org? Delete the whole org instead: sf org delete scratch --target-org <alias>
    Bash version: scripts/uninstall.sh

.EXAMPLE
    .\scripts\uninstall.ps1 -Org nxp-qa
.EXAMPLE
    .\scripts\uninstall.ps1 -Org nxp-qa -Mode package
.EXAMPLE
    .\scripts\uninstall.ps1 -Org nxp-dev -Purge -Yes
    Hard-delete the objects (not allowed in production) without a confirmation prompt.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Org,
    [ValidateSet('source', 'package')][string]$Mode = 'source',
    [switch]$Purge,
    [switch]$Yes,
    [ValidateSet('NoTestRun', 'RunLocalTests', 'RunAllTestsInOrg')][string]$TestLevel
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Set-Location $RepoRoot
Assert-SfCli

$isProd = Test-ProductionOrg $Org
if ($isProd -and $Purge) { throw '-Purge is not allowed in production orgs.' }

$label = "$Mode mode"
if ($isProd) { $label += ', PRODUCTION' }
Write-Host ''
Write-Host "This removes Nexus Pursuit Hub from $Org ($label):" -ForegroundColor Yellow
Write-Host '  - stops the NXP scheduled jobs and removes the NXP permission set assignments'
Write-Host '  - deletes every NXP_ component, and with the NXP objects all their records'
Write-Host '    (notices, searches, matches, push logs, feed runs). Without -Purge, deleted objects stay'
Write-Host '    under Setup > Object Manager > Deleted Objects for 15 days.'
Write-Host 'First delete by hand: the Nexus Pursuit Assistant agent and its NXP agent actions, the NXP prompt'
Write-Host 'templates, and reports, flows or list views built on NXP objects. They block the delete otherwise.'
if (-not $Yes) {
    $answer = Read-Host "Type the org alias ($Org) to continue"
    if ($answer -ne $Org) { throw 'Stopped. Nothing was changed.' }
}

Write-Step 'Stopping jobs and removing permission set assignments'
Invoke-ApexFile 'scripts/uninstall/pre-uninstall.apex' $Org

$reversed = @($PackageDirs)
[array]::Reverse($reversed)

if ($Mode -eq 'package') {
    $installed = Invoke-SfJson @('package', 'installed', 'list', '--target-org', $Org)
    if ($installed.status -ne 0) { throw "Could not list installed packages: $($installed.message)" }
    foreach ($dir in $reversed) {
        $name = Split-Path $dir -Leaf
        $pkg = @($installed.result | Where-Object { $_.SubscriberPackageName -eq $name }) | Select-Object -First 1
        if (-not $pkg) {
            Write-Host "$name is not installed; skipping" -ForegroundColor Yellow
            continue
        }
        Write-Step "Uninstalling $name ($($pkg.SubscriberPackageVersionId))"
        Invoke-Sf @('package', 'uninstall', '--package', $pkg.SubscriberPackageVersionId, '--target-org', $Org, '--wait', '30')
    }
}
else {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('nxp-uninstall-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $emptyPackage = @(
            '<?xml version="1.0" encoding="UTF-8"?>',
            '<Package xmlns="http://soap.sforce.com/2006/04/metadata">',
            "    <version>$ApiVersion</version>",
            '</Package>'
        ) -join "`n"
        Set-Content -Path (Join-Path $work 'package.xml') -Value $emptyPackage -Encoding ASCII
        $extra = @('--ignore-warnings')
        if ($Purge) { $extra += '--purge-on-delete' }
        if ($TestLevel) { $extra += @('--test-level', $TestLevel) }

        # One deployment per package, dependents first, so nothing still in the org refers to what is deleted.
        foreach ($dir in $reversed) {
            Write-Step "Deleting the components in $dir"
            $gen = Join-Path $work 'gen'
            if (Test-Path $gen) { Remove-Item -Recurse -Force $gen }
            New-Item -ItemType Directory -Path $gen | Out-Null
            Invoke-Sf @('project', 'generate', 'manifest', '--source-dir', $dir, '--api-version', $ApiVersion, '--output-dir', $gen) | Out-Null
            Move-Item -Force (Join-Path $gen 'package.xml') (Join-Path $work 'destructiveChangesPost.xml')
            Invoke-Sf (@('project', 'deploy', 'start', '--manifest', (Join-Path $work 'package.xml'),
                    '--post-destructive-changes', (Join-Path $work 'destructiveChangesPost.xml'),
                    '--target-org', $Org, '--api-version', $ApiVersion, '--wait', '60') + $extra)
        }
    }
    finally {
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host "Nexus Pursuit Hub was removed from $Org." -ForegroundColor Green
Write-Host 'Left in place on purpose: Opportunity records created by pushes and any Data Cloud data'
Write-Host 'streams for NXP_Awards. The SAM.gov API key was removed with the NXP External Credential.'
Write-Host 'If a step failed, fix what it names (usually something built by hand) and run the script again;'
Write-Host 'components that are already gone are skipped.'
