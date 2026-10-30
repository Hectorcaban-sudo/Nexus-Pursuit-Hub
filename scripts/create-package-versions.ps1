<#
.SYNOPSIS
    Create unlocked package versions in dependency order (PowerShell version of create-package-versions.sh).

.DESCRIPTION
    The Dev Hub is your production org. First time only, create the seven packages with -CreatePackages.
    Promote each version after QA:
      sf package version promote --package <alias@x.y.z-n> --target-dev-hub <devhub>

.EXAMPLE
    .\scripts\create-package-versions.ps1 -DevHub nxp-hub -CreatePackages
.EXAMPLE
    .\scripts\create-package-versions.ps1 -DevHub nxp-hub -InstallationKey 'MyKey123'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DevHub,
    [string]$InstallationKey,
    [switch]$CreatePackages
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Set-Location $RepoRoot
Assert-SfCli

foreach ($dir in $PackageDirs) {
    $name = Split-Path $dir -Leaf
    if ($CreatePackages) {
        Write-Step "Creating package $name"
        Invoke-Sf @('package', 'create', '--name', $name, '--package-type', 'Unlocked', '--path', $dir,
            '--no-namespace', '--target-dev-hub', $DevHub)
    }
    Write-Step "New version of $name"
    $keyArgs = @('--installation-key-bypass')
    if ($InstallationKey) { $keyArgs = @('--installation-key', $InstallationKey) }
    Invoke-Sf (@('package', 'version', 'create', '--package', $name) + $keyArgs +
        @('--code-coverage', '--target-dev-hub', $DevHub, '--wait', '60'))
}
Write-Host ''
Write-Host "Promote each version after QA: sf package version promote --package <alias@x.y.z-n> --target-dev-hub $DevHub" -ForegroundColor Green
