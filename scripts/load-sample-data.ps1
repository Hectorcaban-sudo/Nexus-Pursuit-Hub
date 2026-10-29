<#
.SYNOPSIS
    Load the Nexus Pursuit Hub sample data into a dev, QA or scratch org. Safe to run again.

.DESCRIPTION
    Loads a sample Company Profile, 7 agencies, 2 contract vehicles, 10 SAMPLE notices (scored on
    insert), 3 saved searches for you, and the search matches and alerts they produce.
    Refuses to run against a production org unless -AllowProduction is given.
    Bash version: scripts/load-sample-data.sh

.EXAMPLE
    .\scripts\load-sample-data.ps1 -Org nxp-dev
    Load (or refresh) the sample data.
.EXAMPLE
    .\scripts\load-sample-data.ps1 -Org nxp-dev -Reset
    Delete the sample data first, then load it again.
.EXAMPLE
    .\scripts\load-sample-data.ps1 -Org nxp-dev -Delete
    Only delete the sample data.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Org,
    [switch]$Reset,
    [switch]$Delete,
    [switch]$AllowProduction
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Set-Location $RepoRoot
Assert-SfCli

if ((Test-ProductionOrg $Org) -and -not $AllowProduction) {
    throw "$Org is a production org. Sample data is for dev, QA and scratch orgs only (override: -AllowProduction)."
}

if ($Reset -or $Delete) {
    Write-Step 'Deleting existing sample data'
    Invoke-ApexFile 'scripts/apex/delete-sample-data.apex' $Org
    if ($Delete) {
        Write-Host 'Sample data deleted.' -ForegroundColor Green
        return
    }
}

Write-Step 'Company Profile (before the notices, so they are scored as they load)'
Invoke-ApexFile 'scripts/apex/seed-profile.apex' $Org

# Order matters: departments, then agencies, then notices.
$loads = @(
    @{ File = 'data/seed/1-NXP_Gov_Agency__c-departments.csv'; Object = 'NXP_Gov_Agency__c'; ExternalId = 'Agency_Code__c' },
    @{ File = 'data/seed/2-NXP_Gov_Agency__c-agencies.csv'; Object = 'NXP_Gov_Agency__c'; ExternalId = 'Agency_Code__c' },
    @{ File = 'data/seed/3-NXP_Contract_Vehicle__c.csv'; Object = 'NXP_Contract_Vehicle__c'; ExternalId = 'Vehicle_Code__c' },
    @{ File = 'data/seed/4-NXP_Gov_Notice__c.csv'; Object = 'NXP_Gov_Notice__c'; ExternalId = 'Notice_Id__c' }
)
foreach ($load in $loads) {
    Write-Step "Upserting $(Split-Path $load.File -Leaf) into $($load.Object) (by $($load.ExternalId))"
    # The CSV files are stored with LF line endings (.gitattributes), also on Windows.
    Invoke-Sf @('data', 'upsert', 'bulk', '--sobject', $load.Object, '--file', $load.File, '--external-id', $load.ExternalId,
        '--line-ending', 'LF', '--wait', '10', '--target-org', $Org)
}

Write-Step 'Setting sample dates relative to today'
Invoke-ApexFile 'scripts/apex/refresh-sample-dates.apex' $Org

Write-Step 'Saved searches and matching'
Invoke-ApexFile 'scripts/apex/seed-searches.apex' $Org

Write-Host ''
Write-Host "Sample data loaded into $Org. Matching runs in the background and takes about a minute." -ForegroundColor Green
Write-Host "  Test everything:  .\scripts\test-functional.ps1 -Org $Org"
Write-Host "  Look around:      sf org open --target-org $Org --path /lightning/n/NXP_Match_Inbox"
