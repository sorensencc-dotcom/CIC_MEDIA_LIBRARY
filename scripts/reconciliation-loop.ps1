#Requires -Version 7.0
param(
  [string]$Domain = "documentary",
  [bool]$GenerateReport = $false,
  [bool]$IngestNewResults = $true,
  [bool]$UpdateGaps = $true,
  [bool]$DryRun = $false,
  [string]$ReportsPath = "C:\CIC_MEDIA_LIBRARY\CIC\reports",
  [string]$MetadataPath = "C:\CIC_MEDIA_LIBRARY\CIC\metadata",
  [string]$ScriptsPath = "C:\CIC_MEDIA_LIBRARY\CIC\scripts"
)

$ErrorActionPreference = "Stop"

$LogFile = Join-Path $MetadataPath "reconciliation_log.md"
$CrawlQueueFile = Join-Path $MetadataPath "archive_crawl_queue.json"
$CrawlLogFile = Join-Path $MetadataPath "archive_crawl_log.md"
$GapsFile = Join-Path $ReportsPath "report_gaps_latest.md"
$InterviewPromptsFile = Join-Path $MetadataPath "interview_prompts_latest.json"
$EntityGraphFile = Join-Path $MetadataPath "entity_graph.json"

function Log-Message {
  param([string]$Message, [string]$Level = "INFO")
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $formatted = "[$timestamp] [$Level] $Message"
  Write-Host $formatted
}

function Initialize-LogFile {
  if (-not (Test-Path $LogFile)) {
    @"
# Reconciliation Loop Log

This log tracks all Phase 55B reconciliation iterations.

"@ | Set-Content $LogFile
  }
}

function Initialize-CrawlQueue {
  if (-not (Test-Path $CrawlQueueFile)) {
    $queue = @{
      created   = Get-Date -Format 'o'
      items     = @()
      completed = 0
      failed    = 0
    }
    $queue | ConvertTo-Json -Depth 5 | Set-Content $CrawlQueueFile
  }
}

function Parse-GapsForArchiveDirectives {
  param([string]$GapsMarkdown)

  if (-not (Test-Path $GapsMarkdown)) {
    Log-Message "Gaps file not found: $GapsMarkdown" "WARN"
    return @()
  }

  $content = Get-Content $GapsMarkdown -Raw
  $directives = @()

  $lines = $content -split "`n"
  $i = 0

  while ($i -lt $lines.Count) {
    $line = $lines[$i].Trim()

    if ($line -match "^## No documents found: (.+)$") {
      $entity = $matches[1]
      $i++

      $priority = "Medium"
      $recommendation = ""

      while ($i -lt $lines.Count) {
        $currentLine = $lines[$i].Trim()

        if ($currentLine -match "\*\*Priority:\*\*\s+(.+?)\s+\|") {
          $priority = $matches[1]
        }

        if ($currentLine -match "^Search |^Contact |^Add ") {
          $recommendation = $currentLine
          $i++
          break
        }

        if ($currentLine -match "^##") { break }
        $i++
      }

      $directive = Build-ArchiveSearchDirective -Gap $entity -Priority $priority
      if ($directive) {
        $directives += $directive
      }

      continue
    }

    $i++
  }

  return $directives
}

function Build-ArchiveSearchDirective {
  param([string]$Gap, [string]$Priority)

  $directives = @()

  if ($Gap -match "Sorensen.*early life.*1881.*1904") {
    $directives += @{
      query           = "Sorensen Denmark 1881 1904 early life"
      domain          = "genealogy"
      priority        = $Priority
      gap_source      = $Gap
      suggested_connectors = @("Rigsarkivet", "FamilySearch")
      max_attempts    = 3
      retry_backoff   = 2000
    }
  }
  elseif ($Gap -match "Willow Run.*construction.*1941.*1942") {
    $directives += @{
      query           = "Willow Run B-24 Ford construction 1941 1942"
      domain          = "documentary"
      priority        = $Priority
      gap_source      = $Gap
      suggested_connectors = @("NARA", "BensonFord")
      max_attempts    = 3
      retry_backoff   = 2000
    }
  }
  elseif ($Gap -match "Ford.*1944|departure.*Ford") {
    $directives += @{
      query           = "Charles Sorensen Ford departure 1944"
      domain          = "documentary"
      priority        = $Priority
      gap_source      = $Gap
      suggested_connectors = @("BensonFord", "BurtonDPL")
      max_attempts    = 3
      retry_backoff   = 2000
    }
  }
  elseif ($Gap -match "Post-Ford.*career.*1944.*1968") {
    $directives += @{
      query           = "Charles Sorensen Willys-Overland post-Ford career 1944 1968"
      domain          = "documentary"
      priority        = $Priority
      gap_source      = $Gap
      suggested_connectors = @("InternetArchive", "Smithsonian")
      max_attempts    = 3
      retry_backoff   = 2000
    }
  }

  return $directives
}

function Enqueue-CrawlTargets {
  param([array]$Directives)

  if ($Directives.Count -eq 0) {
    Log-Message "No directives to enqueue" "INFO"
    return
  }

  $queue = if (Test-Path $CrawlQueueFile) {
    Get-Content $CrawlQueueFile | ConvertFrom-Json
  }
  else {
    @{ items = @(); completed = 0; failed = 0 }
  }

  foreach ($directive in $Directives) {
    $existingItem = $queue.items | Where-Object { $_.query -eq $directive.query -and $_.domain -eq $directive.domain }

    if (-not $existingItem) {
      $directive | Add-Member -NotePropertyName "id" -NotePropertyValue "crawl_$(New-Guid)" -Force
      $directive | Add-Member -NotePropertyName "status" -NotePropertyValue "pending" -Force
      $directive | Add-Member -NotePropertyName "created" -NotePropertyValue (Get-Date -Format 'o') -Force
      $directive | Add-Member -NotePropertyName "executed" -NotePropertyValue $false -Force
      $directive | Add-Member -NotePropertyName "results_count" -NotePropertyValue 0 -Force

      $queue.items += $directive

      Log-Message "Queued: $($directive.query) [$($directive.priority)]" "INFO"
    }
  }

  $queue | ConvertTo-Json -Depth 10 | Set-Content $CrawlQueueFile
  Log-Message "Total queued items: $($queue.items.Count)" "INFO"
}

function Execute-CrawlQueue {
  param([bool]$DryRun = $false)

  if (-not (Test-Path $CrawlQueueFile)) {
    Log-Message "No crawl queue found" "WARN"
    return
  }

  $queue = Get-Content $CrawlQueueFile | ConvertFrom-Json
  $pendingItems = $queue.items | Where-Object { $_.status -eq "pending" }

  if ($pendingItems.Count -eq 0) {
    Log-Message "No pending crawl items" "INFO"
    return
  }

  Log-Message "Executing $($pendingItems.Count) pending crawls" "INFO"

  foreach ($item in $pendingItems) {
    Log-Message "Crawl: $($item.query) (Domain: $($item.domain)) [DryRun: $DryRun]" "INFO"

    if (-not $DryRun) {
      $queryArgs = @{
        Query   = $item.query
        Domain  = $item.domain
        MaxResults = 15
      }

      try {
        $results = & "$ScriptsPath\query-archives.ps1" @queryArgs 2>&1

        if ($results -and $results.Count -gt 0) {
          $item.results_count = $results.Count
          $item.status = "completed"
          $item.executed = $true
          $item.executed_at = Get-Date -Format 'o'

          Log-Message "✓ Crawl complete: $($results.Count) results" "INFO"
        }
        else {
          $item.status = "no_results"
          $item.executed = $true
          Log-Message "⚠ No results for query" "WARN"
        }
      }
      catch {
        $item.status = "failed"
        $item.error = $_.Exception.Message
        $queue.failed += 1

        Log-Message "✗ Crawl failed: $_" "ERROR"
      }
    }
    else {
      Log-Message "[DRY RUN] Would execute: $($item.query)" "INFO"
    }
  }

  $queue | ConvertTo-Json -Depth 10 | Set-Content $CrawlQueueFile

  $completed = ($queue.items | Where-Object { $_.executed -eq $true }).Count
  Log-Message "Crawl execution complete: $completed/$($queue.items.Count) items" "INFO"
}

function Generate-ReportIfNeeded {
  if (-not $GenerateReport) {
    Log-Message "Skipping report generation (GenerateReport = false)" "INFO"
    return
  }

  Log-Message "Generating fresh report..." "INFO"

  try {
    & "$ScriptsPath\generate-report.ps1" -Domain $Domain -RunArchiveQuery
    Log-Message "✓ Report generated" "INFO"
  }
  catch {
    Log-Message "✗ Report generation failed: $_" "ERROR"
    throw
  }
}

function Convert-GapsToInterviewPrompts {
  if (-not (Test-Path $GapsFile)) {
    Log-Message "Gaps file not found: $GapsFile" "WARN"
    return
  }

  Log-Message "Converting gaps to interview prompts..." "INFO"

  try {
    & "$ScriptsPath\gap-to-interview-prompts.ps1" `
      -GapsMarkdown $GapsFile `
      -Domain $Domain `
      -OutputJson $InterviewPromptsFile

    Log-Message "✓ Interview prompts generated" "INFO"
  }
  catch {
    Log-Message "✗ Interview prompt conversion failed: $_" "ERROR"
  }
}

function Report-GapReconciliation {
  param([string]$IterationId)

  Log-Message "Generating reconciliation report..." "INFO"

  $reportText = @"
## Reconciliation Iteration: $IterationId

**Timestamp:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

### Workflow Summary

- **Domain:** $Domain
- **Generate Report:** $GenerateReport
- **Ingest Results:** $IngestNewResults
- **Update Gaps:** $UpdateGaps

### Archive Directives Generated

"@

  if (Test-Path $CrawlQueueFile) {
    $queue = Get-Content $CrawlQueueFile | ConvertFrom-Json
    $reportText += "`nTotal queued items: $($queue.items.Count)`n"
    $reportText += "`nQueued directives:`n"

    foreach ($item in $queue.items) {
      $reportText += "`n- **$($item.query)**`n"
      $reportText += "  - Domain: $($item.domain)`n"
      $reportText += "  - Priority: $($item.priority)`n"
      $reportText += "  - Status: $($item.status)`n"
    }
  }

  $reportText += "`n### Interview Prompts Generated`n"

  if (Test-Path $InterviewPromptsFile) {
    try {
      $prompts = Get-Content $InterviewPromptsFile | ConvertFrom-Json
      $reportText += "`nTotal prompts: $($prompts.total_prompts)`n"
      $reportText += "`nPriority breakdown:`n"

      $highCount = ($prompts.prompts | Where-Object { $_.priority -eq "High" }).Count
      $mediumCount = ($prompts.prompts | Where-Object { $_.priority -eq "Medium" }).Count
      $lowCount = ($prompts.prompts | Where-Object { $_.priority -eq "Low" }).Count

      $reportText += "- High: $highCount`n"
      $reportText += "- Medium: $mediumCount`n"
      $reportText += "- Low: $lowCount`n"
    }
    catch {
      $reportText += "`n⚠ Could not parse interview prompts: $_`n"
    }
  }

  $reportText += "`n---`n`n"

  Add-Content -Path $LogFile -Value $reportText
  Log-Message "✓ Reconciliation report written to log" "INFO"
}

function Main {
  Write-Host ""
  Write-Host "===== RECONCILIATION LOOP START ====="
  Write-Host "Domain: $Domain | GenerateReport: $GenerateReport | DryRun: $DryRun"
  Write-Host ""

  $iterationId = "iter_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

  try {
    Initialize-LogFile
    Initialize-CrawlQueue

    if ($GenerateReport) {
      Generate-ReportIfNeeded
    }

    Convert-GapsToInterviewPrompts

    $directives = Parse-GapsForArchiveDirectives -GapsMarkdown $GapsFile
    Log-Message "Parsed $($directives.Count) archive directives from gaps" "INFO"

    Enqueue-CrawlTargets -Directives $directives

    if ($IngestNewResults) {
      Execute-CrawlQueue -DryRun $DryRun
    }
    else {
      Log-Message "Skipping crawl execution (IngestNewResults = false)" "INFO"
    }

    if ($UpdateGaps) {
      Log-Message "Regenerating report with updated graph..." "INFO"
      & "$ScriptsPath\generate-report.ps1" -Domain $Domain
      Log-Message "✓ Updated report generated" "INFO"
    }

    Report-GapReconciliation -IterationId $iterationId

    Write-Host ""
    Write-Host "===== RECONCILIATION LOOP COMPLETE ====="
    Write-Host "Iteration: $iterationId"
    Write-Host "Log: $LogFile"
    Write-Host "Crawl Queue: $CrawlQueueFile"
    Write-Host ""
  }
  catch {
    Log-Message "FATAL ERROR: $_" "ERROR"
    Write-Error $_.Exception
    exit 1
  }
}

Main
