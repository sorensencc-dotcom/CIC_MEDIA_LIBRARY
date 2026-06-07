<#
.SYNOPSIS
  Query multiple archive APIs simultaneously and normalize results. Phase 53.

.DESCRIPTION
  Discovers and invokes all registered archive connectors matching the current domain.
  Applies per-connector rate limiting and retry logic. Results are normalized into a
  unified schema and written to the metadata directory.

  Live connectors (no setup required):
    LOC           — Library of Congress open API
    Smithsonian   — Smithsonian Open Access (includes NASM, Air & Space)
    ChronAmerica  — Chronicling America, 20M+ newspaper pages 1770–1963

  Credentialed connectors (require setup):
    FamilySearch  — Free API; register at familysearch.org/developers
    Ancestry      — Partner API; apply at ancestry.com/corporate/brands/ancestry/genealogy-api

  Institutional connectors (no API; provides research links):
    BensonFord    — The Henry Ford digital collections (documentary mode only)

.PARAMETER Query
  Search terms. Use quotes for phrases: "Charles Sorensen" "Willow Run"

.PARAMETER Domain
  'documentary' or 'genealogy'. Filters which connectors are invoked.

.PARAMETER Connectors
  Comma-separated connector names to use. Default: all enabled for the domain.
  Example: -Connectors "LOC,ChronAmerica"

.PARAMETER MaxResults
  Max results per connector. Default: 10.

.PARAMETER DateFrom
  Filter: earliest year (e.g. 1930)

.PARAMETER DateTo
  Filter: latest year (e.g. 1960)

.PARAMETER State
  Filter: US state name for newspaper searches (ChronAmerica). e.g. "Michigan"

.PARAMETER OutputPath
  Where to write results. Default: C:\CIC_MEDIA_LIBRARY\CIC\metadata

.PARAMETER CredentialsFile
  Path to JSON file with API credentials. Default: C:\CIC_MEDIA_LIBRARY\CIC\metadata\archive_credentials.json

.PARAMETER RetryCount
  Number of retries on failure. Default: 2

.EXAMPLE
  # CIC search for Sorensen materials
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\query-archives.ps1' `
    -Query "Charles Emil Sorensen" -Domain documentary -DateFrom 1930 -DateTo 1960

.EXAMPLE
  # Genealogy search with newspaper filter to Michigan
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\query-archives.ps1' `
    -Query "Jens Sorensen" -Domain genealogy -State Michigan -MaxResults 20

.EXAMPLE
  # Single connector test
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\query-archives.ps1' `
    -Query "Willow Run bomber plant" -Domain documentary -Connectors LOC
#>

param(
  [Parameter(Mandatory)]
  [string]$Query,

  [ValidateSet('documentary','genealogy')]
  [string]$Domain = "documentary",

  [string]$Connectors    = "",
  [int]$MaxResults       = 10,
  [string]$DateFrom      = "",
  [string]$DateTo        = "",
  [string]$State         = "",
  [string]$OutputPath    = "C:\CIC_MEDIA_LIBRARY\CIC\metadata",
  [string]$CredentialsFile = "C:\CIC_MEDIA_LIBRARY\CIC\metadata\archive_credentials.json",
  [int]$RetryCount       = 2
)

$RootPath = "C:\CIC_MEDIA_LIBRARY\CIC"
$LogPath  = "$RootPath\logs"
$LogFile  = "$LogPath\archive_query_$(Get-Date -Format 'yyyy-MM-dd').log"

if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }

function Write-Log {
  param([string]$Message)
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$ts] $Message" | Add-Content $LogFile
  Write-Host $Message
}

# ---------------------------------------------------------------------------
# CONNECTOR REGISTRY — populated by dot-sourcing connector files
# ---------------------------------------------------------------------------

$script:ConnectorRegistry = @()

$ConnectorDir = "$PSScriptRoot\archive-connectors"
if (-not (Test-Path $ConnectorDir)) {
  Write-Log "ERROR: archive-connectors directory not found at $ConnectorDir"
  exit 1
}

foreach ($f in (Get-ChildItem -Path $ConnectorDir -Filter "*-Connector.ps1" | Sort-Object Name)) {
  try {
    . $f.FullName
    Write-Log "  Loaded connector: $($f.BaseName)"
  } catch {
    Write-Log "  WARN: Failed to load $($f.Name): $_"
  }
}

Write-Log "Registered connectors: $($script:ConnectorRegistry.Count)"

# ---------------------------------------------------------------------------
# CREDENTIALS
# ---------------------------------------------------------------------------

$Creds = @{}
if (Test-Path $CredentialsFile) {
  try {
    $rawCreds = Get-Content $CredentialsFile -Raw | ConvertFrom-Json
    foreach ($prop in $rawCreds.PSObject.Properties) {
      $Creds[$prop.Name] = @{}
      foreach ($kv in $prop.Value.PSObject.Properties) {
        $Creds[$prop.Name][$kv.Name] = $kv.Value
      }
    }
    Write-Log "Credentials loaded for: $($Creds.Keys -join ', ')"
  } catch {
    Write-Log "WARN: Could not parse credentials file: $_"
  }
} else {
  Write-Log "No credentials file found at $CredentialsFile (credentialed connectors will be skipped)"
}

# ---------------------------------------------------------------------------
# FILTER CONNECTORS
# ---------------------------------------------------------------------------

$EnabledNames = @()
if ($Connectors) {
  $EnabledNames = $Connectors -split ',' | ForEach-Object { $_.Trim() }
}

$ActiveConnectors = $script:ConnectorRegistry | Where-Object {
  $c = $_
  $domainMatch = $c.Domains -contains $Domain
  $nameMatch   = ($EnabledNames.Count -eq 0) -or ($EnabledNames -contains $c.Name)
  $domainMatch -and $nameMatch
}

Write-Log "Active connectors for domain '$Domain': $($ActiveConnectors.Name -join ', ')"

# ---------------------------------------------------------------------------
# BUILD FILTERS
# ---------------------------------------------------------------------------

$Filters = @{}
if ($DateFrom) { $Filters.date_from = $DateFrom }
if ($DateTo)   { $Filters.date_to   = $DateTo   }
if ($State)    { $Filters.state     = $State     }

# ---------------------------------------------------------------------------
# RETRY WRAPPER
# ---------------------------------------------------------------------------

function Invoke-WithRetry {
  param([scriptblock]$ScriptBlock, [int]$Retries, [string]$ConnectorName)

  for ($attempt = 1; $attempt -le ($Retries + 1); $attempt++) {
    try {
      return & $ScriptBlock
    } catch {
      if ($attempt -le $Retries) {
        $wait = $attempt * 2000
        Write-Log "  [$ConnectorName] Attempt $attempt failed: $_ — retrying in $($wait/1000)s"
        Start-Sleep -Milliseconds $wait
      } else {
        Write-Log "  [$ConnectorName] All $($Retries+1) attempts failed: $_"
        return @()
      }
    }
  }
}

# ---------------------------------------------------------------------------
# QUERY LOOP
# ---------------------------------------------------------------------------

Write-Log "========== ARCHIVE QUERY START =========="
Write-Log "Query: '$Query' | Domain: $Domain | MaxResults per connector: $MaxResults"

$AllResults    = @()
$ConnectorStats = @{}

foreach ($connector in $ActiveConnectors) {
  Write-Log "  Querying: $($connector.DisplayName)..."

  $creds = if ($Creds.ContainsKey($connector.Name)) { $Creds[$connector.Name] } else { @{} }

  # Wrap in @() to force array — prevents hashtable.Count returning key-count on single-result connectors
  $results = @(Invoke-WithRetry -ConnectorName $connector.Name -Retries $RetryCount -ScriptBlock {
    & $connector.Invoke -Query $Query -Filters $Filters -MaxResults $MaxResults -Credentials $creds
  })

  if ($null -eq $results) { $results = @() }

  # Tag each result with the query context
  foreach ($r in $results) {
    if ($r -isnot [hashtable]) { continue }  # skip any unwrapped non-result output
    $r.query           = $Query
    $r.domain          = $Domain
    $r.retrieved       = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $r.connector_name  = $connector.Name
    $AllResults       += $r
  }

  $validCount = 0
  foreach ($r in $results) { if ($r -is [hashtable]) { $validCount++ } }
  $ConnectorStats[$connector.Name] = $validCount
  Write-Log "  [$($connector.Name)] $validCount results"

  # Per-connector rate limit
  if ($connector.RateLimitMs -and $connector.RateLimitMs -gt 0) {
    Start-Sleep -Milliseconds $connector.RateLimitMs
  }
}

# ---------------------------------------------------------------------------
# SORT BY RELEVANCE
# ---------------------------------------------------------------------------

$AllResults = $AllResults | Sort-Object { -[float]$_.relevance_score }

# ---------------------------------------------------------------------------
# WRITE OUTPUT
# ---------------------------------------------------------------------------

if (-not (Test-Path $OutputPath)) {
  New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$timestamp  = Get-Date -Format 'yyyy-MM-dd_HHmm'
$outputJson = "$OutputPath\archive_results_$timestamp.json"
$outputLatest = "$OutputPath\archive_results_latest.json"

$output = @{
  query       = $Query
  domain      = $Domain
  generated   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  filters     = $Filters
  connectors  = $ConnectorStats
  total_count = $AllResults.Count
  results     = $AllResults
}

$output | ConvertTo-Json -Depth 8 | Set-Content $outputJson    -Encoding UTF8
$output | ConvertTo-Json -Depth 8 | Set-Content $outputLatest  -Encoding UTF8

Write-Log "Results written: $outputJson"

# ---------------------------------------------------------------------------
# MARKDOWN SUMMARY
# ---------------------------------------------------------------------------

$summaryLines = @(
  "# Archive Search Results",
  "",
  "**Query:** $Query",
  "**Domain:** $Domain",
  "**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
  "**Total results:** $($AllResults.Count)",
  "",
  "## Results by Connector",
  "",
  "| Connector | Results |",
  "|-----------|---------|"
)
foreach ($k in ($ConnectorStats.Keys | Sort-Object)) {
  $summaryLines += "| $k | $($ConnectorStats[$k]) |"
}

if ($Filters.Count -gt 0) {
  $summaryLines += @("","## Filters Applied","")
  foreach ($k in $Filters.Keys) { $summaryLines += "- **$k**: $($Filters[$k])" }
}

$summaryLines += @("","## Top Results","")

$topResults = $AllResults | Where-Object { -not $_.requires_manual } | Select-Object -First 15
foreach ($r in $topResults) {
  $score = if ($r.relevance_score) { " (score: $([math]::Round($r.relevance_score,2)))" } else { "" }
  $summaryLines += "### $($r.title)$score"
  $summaryLines += "**Source:** $($r.source_archive) | **Format:** $($r.format) | **Date:** $($r.date)"
  if ($r.description) { $summaryLines += $r.description[0..300] -join "" }
  if ($r.url)         { $summaryLines += "**URL:** $($r.url)" }
  $summaryLines += ""
}

$manualItems = $AllResults | Where-Object { $_.requires_manual }
if ($manualItems.Count -gt 0) {
  $summaryLines += @("## Manual Contact Required","")
  foreach ($r in $manualItems) {
    $summaryLines += "**$($r.source_archive)**"
    $summaryLines += "- URL: $($r.url)"
    if ($r.contact_email) { $summaryLines += "- Contact: $($r.contact_email)" }
    if ($r.notes) { $r.notes | ForEach-Object { $summaryLines += "- $_" } }
    $summaryLines += ""
  }
}

$summaryPath = "$OutputPath\archive_results_latest.md"
$summaryLines | Set-Content $summaryPath -Encoding UTF8

# ---------------------------------------------------------------------------
# CONSOLE SUMMARY
# ---------------------------------------------------------------------------

Write-Log "========== ARCHIVE QUERY COMPLETE =========="
Write-Host ""
Write-Host "✓ ARCHIVE QUERY COMPLETE" -ForegroundColor Green
Write-Host "  Query:   '$Query' [$Domain]"
Write-Host "  Results: $($AllResults.Count) total"
foreach ($k in ($ConnectorStats.Keys | Sort-Object)) {
  $icon = if ($ConnectorStats[$k] -gt 0) { "  ✓" } else { "  -" }
  Write-Host "$icon $k`: $($ConnectorStats[$k]) results"
}
Write-Host "  JSON:    $outputLatest"
Write-Host "  Summary: $summaryPath"
