<#
.SYNOPSIS
    Functional test of Nexus Pursuit Hub in a dev or QA org that has the sample data loaded.

.DESCRIPTION
    1. Apex REST ingestion API: posts data\fixtures\rest-sample-notice.json and checks idempotency.
    2. End-to-end smoke test (scripts\apex\smoke-test.apex): configuration, fit scoring, search
       drafting and preview, saved searches and matches, notice page data, push to TechnoMile
       (preview, guardrail, push, push log), feed console and the digest batch.
    3. Optional: every Apex unit test with code coverage (-ApexTests).
    Load the sample data first: .\scripts\load-sample-data.ps1 -Org <alias>
    Exits with code 0 when nothing failed, 1 otherwise. Bash version: scripts/test-functional.sh

.EXAMPLE
    .\scripts\test-functional.ps1 -Org nxp-dev
.EXAMPLE
    .\scripts\test-functional.ps1 -Org nxp-dev -ApexTests
.EXAMPLE
    .\scripts\test-functional.ps1 -Org nxp-dev -SkipRest
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Org,
    [switch]$ApexTests,
    [switch]$SkipRest
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Set-Location $RepoRoot
Assert-SfCli

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Status, [string]$Check, [string]$Detail) {
    $results.Add([pscustomobject]@{ Status = $Status; Check = $Check; Detail = $Detail })
}

function Send-RestNotice([string]$Endpoint, [string]$Token, [string]$Key, [string]$Body) {
    $headers = @{ Authorization = "Bearer $Token"; 'Idempotency-Key' = $Key }
    try {
        $resp = Invoke-WebRequest -Uri $Endpoint -Method Post -Headers $headers -ContentType 'application/json' `
            -Body ([Text.Encoding]::UTF8.GetBytes($Body)) -UseBasicParsing
        $replay = (@($resp.Headers['Idempotent-Replay']) -join '') -eq 'true'
        return @{ Code = [int]$resp.StatusCode; Body = [string]$resp.Content; Replay = $replay }
    }
    catch {
        $code = 0
        $text = $_.Exception.Message
        if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $text = $_.ErrorDetails.Message }
        return @{ Code = $code; Body = $text; Replay = $false }
    }
}

# 1. Apex REST ingestion API ------------------------------------------------------------------------
if (-not $SkipRest) {
    Write-Step 'Apex REST ingestion API (POST /services/apexrest/nxp/v1/notices)'
    # Windows PowerShell 5.1 does not always offer TLS 1.2 by default; Salesforce requires it.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $info = Invoke-SfJson @('org', 'display', '--target-org', $Org)
    if ($info.status -ne 0 -or -not $info.result.accessToken) {
        Add-Result 'WARN' 'REST ingestion' "could not read the access token from 'sf org display'; skipped"
    }
    else {
        $today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        $due = (Get-Date).ToUniversalTime().AddDays(30).ToString('yyyy-MM-dd')
        $body = (Get-Content -Raw -Encoding UTF8 'data/fixtures/rest-sample-notice.json').Replace('{{TODAY}}', $today).Replace('{{DUE_30}}', $due)
        $key = 'nxp-functional-test-' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $endpoint = $info.result.instanceUrl.TrimEnd('/') + '/services/apexrest/nxp/v1/notices'

        $first = Send-RestNotice $endpoint $info.result.accessToken $key $body
        $ok = $false
        if ($first.Code -eq 200) {
            $json = $first.Body | ConvertFrom-Json
            $ok = ($json.rejected -eq 0) -and (($json.created + $json.updated + $json.unchanged) -eq 1)
        }
        if ($ok) {
            Add-Result 'PASS' 'REST ingestion' "HTTP 200, SAMPLE-REST-0001 accepted: created=$($json.created) updated=$($json.updated) unchanged=$($json.unchanged)"
        }
        else {
            Add-Result 'FAIL' 'REST ingestion' "HTTP $($first.Code) $($first.Body) (the user needs the NXP_Integration or NXP_Admin permission set)"
        }

        $second = Send-RestNotice $endpoint $info.result.accessToken $key $body
        if ($second.Replay) {
            Add-Result 'PASS' 'REST idempotency' 'same Idempotency-Key replayed the first response'
        }
        else {
            Add-Result 'FAIL' 'REST idempotency' 'second call with the same Idempotency-Key was not a replay'
        }
    }
}

# 2. End-to-end smoke test ----------------------------------------------------------------------------
Write-Step 'End-to-end smoke test (fit scoring, searches, matches, push, feeds, digest)'
try {
    $log = Invoke-ApexFile 'scripts/apex/smoke-test.apex' $Org -PassThru
    $lines = @(Get-DebugLines $log | Where-Object { $_ -like 'NXP-SMOKE|*' })
    if (-not ($lines | Where-Object { $_ -like 'NXP-SMOKE|SUMMARY|*' })) {
        Add-Result 'FAIL' 'Smoke test' "no results in the debug log (check the org's debug log levels)"
    }
    foreach ($line in $lines) {
        $parts = $line.Split([char]'|', 4)
        if ($parts.Count -lt 4 -or $parts[1] -eq 'SUMMARY') { continue }
        Add-Result $parts[1] $parts[2] $parts[3]
    }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Add-Result 'FAIL' 'Smoke test' 'anonymous Apex did not run (compile or runtime error above)'
}

# 3. Apex unit tests (optional) -----------------------------------------------------------------------
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
