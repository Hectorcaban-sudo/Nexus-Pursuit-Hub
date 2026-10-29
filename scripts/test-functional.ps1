<#
.SYNOPSIS
    Functional test of Nexus Pursuit Hub in a dev or QA org that has the sample data loaded.

.DESCRIPTION
    Runs scripts\apex\smoke-test.apex: the REST ingestion resource and its idempotency, configuration,
    fit scoring, search drafting and preview, saved searches and matches, notice page data, push to
    TechnoMile (preview, guardrail, push, push log), feed console and the digest batch.
    The smoke test saves its results in an NXP_Log__c row (Source 'NXP-SMOKE'); this script reads
    that row, so results don't depend on the size of the debug log.
    Optional: every Apex unit test with code coverage (-ApexTests).
    Load the sample data first: .\scripts\load-sample-data.ps1 -Org <alias>
    Exits with code 0 when nothing failed, 1 otherwise. Bash version: scripts/test-functional.sh

.EXAMPLE
    .\scripts\test-functional.ps1 -Org nxp-dev
.EXAMPLE
    .\scripts\test-functional.ps1 -Org nxp-dev -ApexTests
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Org,
    [switch]$ApexTests,
    # Kept so older commands still work; the REST check now runs inside the smoke test.
    [switch]$SkipRest
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Set-Location $RepoRoot
Assert-SfCli

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Status, [string]$Check, [string]$Detail) {
    $results.Add([pscustomobject]@{ Status = $Status; Check = $Check; Detail = $Detail })
}

# 1. End-to-end smoke test ----------------------------------------------------------------------------
Write-Step 'End-to-end smoke test (REST API, fit scoring, searches, matches, push, feeds, digest)'
# Two minutes of slack for clock differences between this computer and the org.
$since = (Get-Date).ToUniversalTime().AddMinutes(-2).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
$lines = @()
try {
    $log = Invoke-ApexFile 'scripts/apex/smoke-test.apex' $Org -PassThru
    $query = "SELECT Message__c FROM NXP_Log__c WHERE Source__c = 'NXP-SMOKE' AND CreatedDate >= $since ORDER BY CreatedDate DESC LIMIT 1"
    $saved = Invoke-SfJson @('data', 'query', '--query', $query, '--target-org', $Org)
    if ($saved.status -eq 0 -and @($saved.result.records).Count -gt 0) {
        $lines = @(([string]$saved.result.records[0].Message__c) -split "`r?`n")
    }
    else {
        # Older smoke-test versions only wrote to the debug log.
        $lines = @(Get-DebugLines $log | Where-Object { $_ -like 'NXP-SMOKE|*' } | ForEach-Object { $_.Substring(10) })
    }
    if (-not ($lines | Where-Object { $_ -like 'SUMMARY|*' })) {
        Add-Result 'FAIL' 'Smoke test' 'ran, but no results were found in NXP Logs or the debug log'
    }
    foreach ($line in $lines) {
        $parts = $line.Split([char]'|', 3)
        if ($parts.Count -lt 3 -or $parts[0] -eq 'SUMMARY') { continue }
        Add-Result $parts[0] $parts[1] $parts[2]
    }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Add-Result 'FAIL' 'Smoke test' 'anonymous Apex did not run (compile or runtime error above)'
}

# 2. Apex unit tests (optional) -----------------------------------------------------------------------
if ($ApexTests) {
    Write-Step 'Apex unit tests (RunLocalTests, with coverage)'
    & sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 30 --target-org $Org
    if ($LASTEXITCODE -eq 0) {
        Add-Result 'PASS' 'Apex unit tests' 'all local tests passed'
    }
    else {
        Add-Result 'FAIL' 'Apex unit tests' 'see the test output above'
    }
}

# Report ----------------------------------------------------------------------------------------------
Write-Step "Results for $Org"
$colors = @{ PASS = 'Green'; FAIL = 'Red'; WARN = 'Yellow'; SKIP = 'DarkGray' }
foreach ($r in $results) {
    $color = 'Gray'
    if ($colors.ContainsKey($r.Status)) { $color = $colors[$r.Status] }
    Write-Host ('{0,-5}' -f $r.Status) -ForegroundColor $color -NoNewline
    Write-Host (' {0,-22} {1}' -f $r.Check, $r.Detail)
}
$fails = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
Write-Host ''
if ($fails -eq 0) {
    Write-Host "All checks passed ($($results.Count))." -ForegroundColor Green -NoNewline
    Write-Host ' Next: the manual walkthrough in docs/guides/testing-guide.md'
    exit 0
}
Write-Host "$fails of $($results.Count) checks failed." -ForegroundColor Red
exit 1
