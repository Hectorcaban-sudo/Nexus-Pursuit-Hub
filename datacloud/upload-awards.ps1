<#
.SYNOPSIS
    Bulk-load a USAspending award extract into Data Cloud through the Ingestion API (bulk pattern).
    PowerShell version of upload-awards.sh.

.DESCRIPTION
    Runs on an approved job host outside Salesforce.
    -Tenant  Data Cloud tenant endpoint, e.g. https://<tenant>.c360a.salesforce.com (default: $env:DC_TENANT)
    -Token   Data Cloud access token; exchange a Salesforce OAuth token at /services/a360/token (default: $env:DC_TOKEN)
    -CsvFile CSV with the NXP_Award columns (header row required, max 150 MB per batch)

.EXAMPLE
    $env:DC_TENANT = 'https://mytenant.c360a.salesforce.com'; $env:DC_TOKEN = '...'
    .\datacloud\upload-awards.ps1 -CsvFile .\awards.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CsvFile,
    [string]$Tenant = $env:DC_TENANT,
    [string]$Token = $env:DC_TOKEN
)
$ErrorActionPreference = 'Stop'
if (-not $Tenant) { throw 'Set DC_TENANT or pass -Tenant.' }
if (-not $Token) { throw 'Set DC_TOKEN or pass -Token.' }
if (-not (Test-Path $CsvFile)) { throw "File not found: $CsvFile" }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$base = $Tenant.TrimEnd('/') + '/api/v1/ingest/jobs'
$auth = @{ Authorization = "Bearer $Token" }

$jobBody = @{ object = 'NXP_Award'; sourceName = 'NXP_Awards'; operation = 'upsert' } | ConvertTo-Json
$job = Invoke-RestMethod -Method Post -Uri $base -Headers $auth -ContentType 'application/json' -Body $jobBody
Write-Host "Job $($job.id)"

Invoke-RestMethod -Method Put -Uri "$base/$($job.id)/batches" -Headers $auth -ContentType 'text/csv' `
    -InFile (Resolve-Path $CsvFile).Path | Out-Null
Invoke-RestMethod -Method Patch -Uri "$base/$($job.id)" -Headers $auth -ContentType 'application/json' `
    -Body '{"state":"UploadComplete"}' | Out-Null

Write-Host "Uploaded. Check status: Invoke-RestMethod -Uri $base/$($job.id) -Headers @{ Authorization = 'Bearer <token>' }"
