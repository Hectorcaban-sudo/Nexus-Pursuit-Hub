<#
.SYNOPSIS
    Checks to run before every pull request and before every release (PowerShell version of validate.sh).

.DESCRIPTION
    Local checks: Prettier (Apex, LWC), ESLint (LWC), Jest (LWC) and Code Analyzer when installed.
    With -Org, also a check-only deployment of all six packages with RunLocalTests (nothing is saved).

.EXAMPLE
    .\scripts\validate.ps1
.EXAMPLE
    .\scripts\validate.ps1 -Org nxp-dev
#>
[CmdletBinding()]
param(
    [string]$Org
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Set-Location $RepoRoot

Write-Step 'Prettier (Apex, LWC)'
Invoke-Checked 'npx' @('prettier', '--check', 'packages/**/*.{cls,trigger}', 'packages/**/lwc/**/*.{js,html,css}')

Write-Step 'ESLint (LWC)'
Invoke-Checked 'npx' @('eslint', 'packages/**/lwc/**/*.js')

Write-Step 'Jest (LWC)'
Invoke-Checked 'npm' @('run', '--silent', 'test:unit')

$hasSf = [bool](Get-Command sf -ErrorAction SilentlyContinue)
$hasAnalyzer = $false
if ($hasSf) {
    try {
        $plugins = Invoke-SfJson @('plugins')
        $list = $plugins
        if ($plugins.PSObject.Properties['result']) { $list = $plugins.result }
        $hasAnalyzer = @($list | Where-Object { $_.name -eq '@salesforce/plugin-code-analyzer' }).Count -gt 0
    }
    catch {
        $hasAnalyzer = $false
    }
}
if ($hasAnalyzer) {
    Write-Step 'Code Analyzer'
    Invoke-Sf @('code-analyzer', 'run', '--workspace', 'packages', '--severity-threshold', '2', '--view', 'table')
}
else {
    Write-Step 'Code Analyzer not installed; skipping (sf plugins install code-analyzer)'
}

if ($Org) {
    Assert-SfCli
    Write-Step "Check-only deployment to $Org with RunLocalTests"
    Invoke-Sf (@('project', 'deploy', 'validate', '--source-dir') + $PackageDirs +
        @('--target-org', $Org, '--api-version', $ApiVersion, '--test-level', 'RunLocalTests',
            '--coverage-formatters', 'text', '--wait', '60'))
}
Write-Host ''
Write-Host '==> All checks passed' -ForegroundColor Green
