<#
.SYNOPSIS
    Load a GovWin IQ alert export for the parallel run and compare it with Nexus.

.DESCRIPTION
    The CSV needs the columns in data/govwin/govwin-export-template.csv (see data/govwin/README.md).
    Rows are upserted on GovWin_Id__c, so loading the same export again updates it. Then
    NXP_GovWinCompareBatch sets each alert's result; the Adoption dashboard shows the catch rate.
    Bash version: scripts/load-govwin-export.sh

.EXAMPLE
    .\scripts\load-govwin-export.ps1 -Org nxp-uat -File govwin-week1.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Org,
    [Parameter(Mandatory = $true)][string]$File
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
$FilePath = (Resolve-Path $File).Path
Set-Location $RepoRoot
Assert-SfCli

$header = Get-Content -Path $FilePath -TotalCount 1
if ($header -notmatch 'GovWin_Id__c') {
    throw "$File has no GovWin_Id__c column; rename the columns as in data/govwin/govwin-export-template.csv"
}

Write-Step "Upserting $(Split-Path $FilePath -Leaf) into NXP_GovWin_Alert__c (by GovWin_Id__c)"
Invoke-Sf @('data', 'upsert', 'bulk', '--sobject', 'NXP_GovWin_Alert__c', '--file', $FilePath, '--external-id', 'GovWin_Id__c',
    '--line-ending', 'LF', '--wait', '10', '--target-org', $Org)

Write-Step 'Comparing with Nexus'
Invoke-ApexFile 'scripts/apex/compare-govwin.apex' $Org
Write-Host 'Done. The results appear on the Adoption dashboard in a minute (GovWin parallel run).' -ForegroundColor Green
