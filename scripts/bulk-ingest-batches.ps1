<#
.SYNOPSIS
  Orchestrate bulk ingestion: Ingest → Classify → Organize for each batch.

.DESCRIPTION
  Runs the full pipeline on staged batches:
  1. ingest-cic-archival (HEIC → JPEG, hashing, dedup)
  2. classify-cic-media (topic routing, significance, entities)
  3. organize-cic-media-library (media IDs, folders, inventory)

  Processes batches sequentially, generating logs + reports for each.

.PARAMETER BatchPattern
  Which batches to process (default: "Batch_*" = all)
  Examples: "Batch_Helene*", "Batch_Kroll*", "Batch_Documents"

.PARAMETER StartBatch
  Start from specific batch (for resume-ability)

.PARAMETER SkipIngest
  Skip ingest phase (default: $false)

.PARAMETER ValidateOnly
  Validate existing data without re-processing (default: $false)

.EXAMPLE
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1'
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -BatchPattern "Batch_Helene*"
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-ingest-batches.ps1' -ValidateOnly $true
#>

param(
  [string]$BatchPattern = "Batch_*",
  [string]$StartBatch = "",
  [switch]$SkipIngest = $false,
  [switch]$ValidateOnly = $false
)

$RootPath = "C:\CIC_MEDIA_LIBRARY\CIC"
$StagingPath = "$RootPath\media\_Inbox"
$LogPath = "$RootPath\logs"
$LogFile = "$LogPath\bulk_ingest_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$timestamp] [$Level] $Message" | Add-Content $LogFile

  $color = switch ($Level) {
    "ERROR" { "Red" }
    "WARN" { "Yellow" }
    "OK" { "Green" }
    default { "White" }
  }
  Write-Host $Message -ForegroundColor $color
}

Write-Log "========== BULK INGESTION WORKFLOW START ==========" "INFO"
Write-Log "Batch pattern: $BatchPattern" "INFO"
Write-Log "Skip ingest: $SkipIngest" "INFO"
Write-Log "Validate only: $ValidateOnly" "INFO"

# Find all batches
$batches = @(Get-ChildItem -Path $StagingPath -Directory -Filter $BatchPattern -ErrorAction SilentlyContinue)

if ($batches.Count -eq 0) {
  Write-Log "No batches found matching: $BatchPattern" "ERROR"
  exit 1
}

Write-Log "Found $($batches.Count) batches to process" "INFO"

$overallReport = @{
  timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  total_batches = $batches.Count
  batches_processed = 0
  batches_failed = 0
  total_files = 0
  total_media_ids_assigned = 0
  batch_details = @()
  errors = @()
}

# MAIN BATCH PROCESSING LOOP
foreach ($batch in $batches) {
  $batchName = $batch.Name
  $batchPath = $batch.FullName

  # Skip batches before StartBatch if specified
  if ($StartBatch -and $batchName -lt $StartBatch) {
    Write-Log "Skipping batch (before $StartBatch): $batchName" "WARN"
    continue
  }

  Write-Log "========== PROCESSING: $batchName ==========" "INFO"

  $batchReport = @{
    batch_name = $batchName
    status = "PENDING"
    files_found = 0
    files_ingested = 0
    files_classified = 0
    files_organized = 0
    media_ids_assigned = @()
    errors = @()
  }

  # Count files in batch
  $filesInBatch = @(Get-ChildItem -Path $batchPath -File -Recurse)
  $batchReport.files_found = $filesInBatch.Count
  Write-Log "  Files in batch: $($batchReport.files_found)" "INFO"

  # PHASE 1: INGEST
  if (-not $SkipIngest -and -not $ValidateOnly) {
    Write-Log "  PHASE 1: INGEST (HEIC → JPEG)" "INFO"

    try {
      & "$RootPath\scripts\ingest-cic-archival.ps1" `
        -InputPath $batchPath `
        -ErrorAction Stop 2>&1 | ForEach-Object {
          Write-Log "    $_" "INFO"
        }

      $batchReport.files_ingested = $batchReport.files_found
      Write-Log "  ✓ Ingest complete: $($batchReport.files_ingested) files" "OK"
    }
    catch {
      Write-Log "  ✗ INGEST FAILED: $_" "ERROR"
      $batchReport.errors += "Ingest failed: $_"
      $batchReport.status = "FAILED"
      $overallReport.batches_failed += 1
      continue
    }
  }

  # PHASE 2: CLASSIFY
  if (-not $ValidateOnly) {
    Write-Log "  PHASE 2: CLASSIFY" "INFO"

    try {
      $classifiedPath = "$batchPath\..\classified_$batchName"
      if (-not (Test-Path $classifiedPath)) {
        New-Item -ItemType Directory -Path $classifiedPath -Force | Out-Null
      }

      & "$RootPath\scripts\classify-cic-media.ps1" `
        -InputPath $classifiedPath `
        -ErrorAction Stop 2>&1 | ForEach-Object {
          Write-Log "    $_" "INFO"
        }

      $batchReport.files_classified = $batchReport.files_ingested
      Write-Log "  ✓ Classification complete: $($batchReport.files_classified) files" "OK"
    }
    catch {
      Write-Log "  ✗ CLASSIFICATION FAILED: $_" "ERROR"
      $batchReport.errors += "Classification failed: $_"
      $batchReport.status = "FAILED"
      $overallReport.batches_failed += 1
      continue
    }
  }

  # PHASE 3: ORGANIZE
  if (-not $ValidateOnly) {
    Write-Log "  PHASE 3: ORGANIZE (Media IDs + DAM Structure)" "INFO"

    try {
      & "$RootPath\scripts\organize-cic-media-library.ps1" `
        -Validate $true `
        -ErrorAction Stop 2>&1 | ForEach-Object {
          Write-Log "    $_" "INFO"
        }

      # Count assigned media IDs from latest inventory
      $inventory = @(Import-Csv -Path "$RootPath\metadata\master_media_inventory.csv" -ErrorAction SilentlyContinue)
      $batchReport.media_ids_assigned = @($inventory.media_id)
      $batchReport.files_organized = $batchReport.files_classified

      Write-Log "  ✓ Organization complete: $($batchReport.files_organized) files" "OK"
      Write-Log "  ✓ Media IDs assigned: $($batchReport.media_ids_assigned.Count) total in inventory" "OK"
    }
    catch {
      Write-Log "  ✗ ORGANIZATION FAILED: $_" "ERROR"
      $batchReport.errors += "Organization failed: $_"
      $batchReport.status = "FAILED"
      $overallReport.batches_failed += 1
      continue
    }
  }

  # Mark batch as complete
  if ($batchReport.status -ne "FAILED") {
    $batchReport.status = "COMPLETE"
    $overallReport.batches_processed += 1
  }

  $overallReport.total_files += $batchReport.files_found
  $overallReport.total_media_ids_assigned = $batchReport.media_ids_assigned.Count
  $overallReport.batch_details += $batchReport

  Write-Log "✓ BATCH COMPLETE: $batchName" "OK"
  Write-Log "" "INFO"
}

# FINAL SUMMARY
Write-Log "========== BULK INGESTION WORKFLOW COMPLETE ==========" "INFO"
Write-Log "Batches processed: $($overallReport.batches_processed)/$($overallReport.total_batches)" "INFO"
Write-Log "Batches failed: $($overallReport.batches_failed)" "WARN"
Write-Log "Total files ingested: $($overallReport.total_files)" "INFO"
Write-Log "Total media IDs in inventory: $($overallReport.total_media_ids_assigned)" "OK"

# Save overall report
$reportPath = "$LogPath\bulk_ingest_report_$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
$overallReport | ConvertTo-Json -Depth 10 | Set-Content $reportPath
Write-Log "Report saved: $reportPath" "INFO"

if ($overallReport.batches_failed -gt 0) {
  Write-Host "`n⚠ BULK INGESTION COMPLETE WITH ERRORS" -ForegroundColor Yellow
  Write-Host "  Review errors and re-run failed batches" -ForegroundColor Yellow
} else {
  Write-Host "`n✓ BULK INGESTION WORKFLOW SUCCESS" -ForegroundColor Green
  Write-Host "  Next: & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\maintain-research-log.ps1' -Topic all" -ForegroundColor Cyan
}
