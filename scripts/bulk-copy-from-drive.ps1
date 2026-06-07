<#
.SYNOPSIS
  Bulk copy all Cast Iron Charlie assets from Google Drive to local staging.
  Organizes by content type/source. Generates inventory + topic mapping.

.DESCRIPTION
  Copies from: G:\My Drive\Cast Iron Charlie — Documentary Project\
  To: C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\

  Creates batches:
  - Batch_Helene_Yacht (Family Archive Helene photos)
  - Batch_Kroll_Willow_Run (Kroll Willow Run photographs)
  - Batch_Family_Archive (Other family photos)
  - Batch_Documents (All Word, PDF, TXT, MD files)
  - Batch_Research (Existing research logs, Treatment versions)

  Generates:
  - drive_copy_manifest.json (file inventory + metadata)
  - folder_to_topic_mapping.json (Drive folder → DAM topic)

.PARAMETER DriveRoot
  Path to Cast Iron Charlie on Drive (default: G:\My Drive\Cast Iron Charlie — Documentary Project)

.PARAMETER LocalStaging
  Local staging directory (default: C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox)

.PARAMETER DryRun
  Show what would be copied without actually copying (default: $false)

.EXAMPLE
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-copy-from-drive.ps1'
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-copy-from-drive.ps1' -DryRun $true
#>

param(
  [string]$DriveRoot = "G:\My Drive\Cast Iron Charlie — Documentary Project",
  [string]$LocalStaging = "C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox",
  [switch]$DryRun = $false
)

$RootPath = "C:\CIC_MEDIA_LIBRARY\CIC"
$LogPath = "$RootPath\logs"
$LogFile = "$LogPath\bulk_copy_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log {
  param([string]$Message)
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$timestamp] $Message" | Add-Content $LogFile
  Write-Host $Message
}

# Folder mapping: Drive source → DAM topic
$FolderMapping = @{
  'Photographs — Family Archive/Personal & Residential/Helene' = @{
    dam_topic = '3-M_Y_Helene_Yacht'
    batch_name = 'Batch_Helene_Yacht'
    description = 'M/Y Helene yacht photographs from family archive'
  }
  'Photographs — Family Archive/Willow Run (1941–1945)/Mike Kroll' = @{
    dam_topic = '1-Willow_Run_Bomber_Plant'
    batch_name = 'Batch_Kroll_Willow_Run'
    description = 'Kroll Willow Run photographs and research images'
  }
  'Photographs — Family Archive/Later in Life' = @{
    dam_topic = '2-CESOR_Charles_Emil_Sorensen'
    batch_name = 'Batch_Sorensen_Later_Life'
    description = 'Charles Emil Sorensen later life and personal photos'
  }
  'Photographs — Family Archive/Willys-Overland & Jeep' = @{
    dam_topic = '9-Willys_Overland_History'
    batch_name = 'Batch_Willys_Photos'
    description = 'Willys-Overland and Jeep related photographs'
  }
}

Write-Log "========== BULK COPY FROM DRIVE START =========="
Write-Log "Drive root: $DriveRoot"
Write-Log "Local staging: $LocalStaging"
Write-Log "DryRun: $DryRun"

if (-not (Test-Path $DriveRoot)) {
  Write-Log "ERROR: Drive root does not exist: $DriveRoot"
  exit 1
}

if (-not (Test-Path $LocalStaging)) {
  New-Item -ItemType Directory -Path $LocalStaging -Force | Out-Null
  Write-Log "Created staging directory: $LocalStaging"
}

$copyReport = @{
  timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  dry_run = $DryRun
  batches = @()
  total_files = 0
  total_size_bytes = 0
  errors = 0
}

# BATCH 1: HELENE YACHT PHOTOS
Write-Log "========== BATCH 1: HELENE YACHT PHOTOS =========="

$heleneSources = @(
  "$DriveRoot/Photographs — Family Archive/Personal & Residential/Helene"
)

foreach ($source in $heleneSources) {
  if (-not (Test-Path $source)) {
    Write-Log "⚠ Source not found: $source"
    continue
  }

  $batchDir = Join-Path $LocalStaging "Batch_Helene_Yacht"
  if (-not $DryRun) {
    if (-not (Test-Path $batchDir)) {
      New-Item -ItemType Directory -Path $batchDir -Force | Out-Null
    }
  }

  $files = @(Get-ChildItem -Path $source -File -Recurse -ErrorAction SilentlyContinue)
  Write-Log "  Found $($files.Count) files in Helene archive"

  $batchStats = @{
    batch_name = "Batch_Helene_Yacht"
    dam_topic = "3-M_Y_Helene_Yacht"
    source_folder = $source
    file_count = $files.Count
    total_size_bytes = ($files | Measure-Object -Property Length -Sum).Sum
    files = @()
  }

  foreach ($file in $files) {
    if ($file.Extension -match '\.(jpg|jpeg|png|pdf|heic|gif)$') {
      $destPath = Join-Path $batchDir $file.Name

      if (-not $DryRun) {
        Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
        if (Test-Path $destPath) {
          Write-Log "  ✓ Copied: $($file.Name)"
        } else {
          Write-Log "  ✗ ERROR copying: $($file.Name)"
          $copyReport.errors += 1
        }
      } else {
        Write-Log "  [DRY RUN] Would copy: $($file.Name) → $batchDir"
      }

      $batchStats.files += @{
        name = $file.Name
        size_bytes = $file.Length
        source = $file.FullName
      }
    }
  }

  $copyReport.batches += $batchStats
  $copyReport.total_files += $batchStats.file_count
  $copyReport.total_size_bytes += $batchStats.total_size_bytes
}

# BATCH 2: KROLL WILLOW RUN PHOTOS
Write-Log "========== BATCH 2: KROLL WILLOW RUN PHOTOS =========="

$krollSource = "$DriveRoot/Photographs — Family Archive/Willow Run (1941–1945)/Mike Kroll"

if (Test-Path $krollSource) {
  $batchDir = Join-Path $LocalStaging "Batch_Kroll_Willow_Run"
  if (-not $DryRun) {
    if (-not (Test-Path $batchDir)) {
      New-Item -ItemType Directory -Path $batchDir -Force | Out-Null
    }
  }

  $files = @(Get-ChildItem -Path $krollSource -File -ErrorAction SilentlyContinue)
  Write-Log "  Found $($files.Count) files in Kroll archive"

  $batchStats = @{
    batch_name = "Batch_Kroll_Willow_Run"
    dam_topic = "1-Willow_Run_Bomber_Plant"
    source_folder = $krollSource
    file_count = $files.Count
    total_size_bytes = ($files | Measure-Object -Property Length -Sum).Sum
    files = @()
  }

  foreach ($file in $files) {
    if ($file.Extension -match '\.(jpg|jpeg|png|heic|gif)$') {
      $destPath = Join-Path $batchDir $file.Name

      if (-not $DryRun) {
        Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
        if (Test-Path $destPath) {
          Write-Log "  ✓ Copied: $($file.Name)"
        } else {
          Write-Log "  ✗ ERROR copying: $($file.Name)"
          $copyReport.errors += 1
        }
      } else {
        Write-Log "  [DRY RUN] Would copy: $($file.Name) → $batchDir"
      }

      $batchStats.files += @{
        name = $file.Name
        size_bytes = $file.Length
        source = $file.FullName
      }
    }
  }

  $copyReport.batches += $batchStats
  $copyReport.total_files += $batchStats.file_count
  $copyReport.total_size_bytes += $batchStats.total_size_bytes
} else {
  Write-Log "⚠ Kroll source not found: $krollSource"
}

# BATCH 3: OTHER FAMILY ARCHIVE PHOTOS
Write-Log "========== BATCH 3: OTHER FAMILY ARCHIVE PHOTOS =========="

$otherPhotoSources = @(
  "$DriveRoot/Photographs — Family Archive/Later in Life",
  "$DriveRoot/Photographs — Family Archive/Willys-Overland & Jeep"
)

foreach ($source in $otherPhotoSources) {
  if (-not (Test-Path $source)) {
    Write-Log "⚠ Source not found: $source"
    continue
  }

  $batchName = if ($source -like "*Later in Life*") { "Batch_Later_Life" } else { "Batch_Willys" }
  $damTopic = if ($source -like "*Later in Life*") { "2-CESOR_Charles_Emil_Sorensen" } else { "9-Willys_Overland_History" }

  $batchDir = Join-Path $LocalStaging $batchName
  if (-not $DryRun) {
    if (-not (Test-Path $batchDir)) {
      New-Item -ItemType Directory -Path $batchDir -Force | Out-Null
    }
  }

  $files = @(Get-ChildItem -Path $source -File -Recurse -ErrorAction SilentlyContinue)
  Write-Log "  Found $($files.Count) files in: $(Split-Path $source -Leaf)"

  $batchStats = @{
    batch_name = $batchName
    dam_topic = $damTopic
    source_folder = $source
    file_count = $files.Count
    total_size_bytes = ($files | Measure-Object -Property Length -Sum).Sum
    files = @()
  }

  foreach ($file in $files) {
    if ($file.Extension -match '\.(jpg|jpeg|png|heic|gif)$') {
      $destPath = Join-Path $batchDir $file.Name

      if (-not $DryRun) {
        Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
        if (Test-Path $destPath) {
          Write-Log "  ✓ Copied: $($file.Name)"
        }
      } else {
        Write-Log "  [DRY RUN] Would copy: $($file.Name) → $batchDir"
      }

      $batchStats.files += @{
        name = $file.Name
        size_bytes = $file.Length
      }
    }
  }

  $copyReport.batches += $batchStats
  $copyReport.total_files += $batchStats.file_count
  $copyReport.total_size_bytes += $batchStats.total_size_bytes
}

# BATCH 4: DOCUMENTS (Word, PDF, TXT, MD)
Write-Log "========== BATCH 4: DOCUMENTS =========="

$docsSource = "$DriveRoot/Documents"

if (Test-Path $docsSource) {
  $batchDir = Join-Path $LocalStaging "Batch_Documents"
  if (-not $DryRun) {
    if (-not (Test-Path $batchDir)) {
      New-Item -ItemType Directory -Path $batchDir -Force | Out-Null
    }
  }

  $files = @(Get-ChildItem -Path $docsSource -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '\.(docx|doc|pdf|txt|md)$' })

  Write-Log "  Found $($files.Count) document files"

  $batchStats = @{
    batch_name = "Batch_Documents"
    dam_topic = "99-Uncategorized"
    source_folder = $docsSource
    file_count = $files.Count
    total_size_bytes = ($files | Measure-Object -Property Length -Sum).Sum
    files = @()
  }

  foreach ($file in $files) {
    $destPath = Join-Path $batchDir $file.Name

    if (-not $DryRun) {
      Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
      if (Test-Path $destPath) {
        Write-Log "  ✓ Copied: $($file.Name) ($($file.Extension))"
      }
    } else {
      Write-Log "  [DRY RUN] Would copy: $($file.Name) → $batchDir"
    }

    $batchStats.files += @{
      name = $file.Name
      size_bytes = $file.Length
      type = $file.Extension
    }
  }

  $copyReport.batches += $batchStats
  $copyReport.total_files += $batchStats.file_count
  $copyReport.total_size_bytes += $batchStats.total_size_bytes
}

# SAVE REPORTS
Write-Log "========== BULK COPY COMPLETE =========="
Write-Log "Total files: $($copyReport.total_files)"
Write-Log "Total size: $([Math]::Round($copyReport.total_size_bytes / 1GB, 2)) GB"
Write-Log "Batches created: $($copyReport.batches.Count)"
Write-Log "Errors: $($copyReport.errors)"

$manifestPath = "$LocalStaging\drive_copy_manifest.json"
$copyReport | ConvertTo-Json -Depth 10 | Set-Content $manifestPath
Write-Log "Manifest saved: $manifestPath"

# Save topic mapping
$mappingPath = "$RootPath\metadata\folder_to_topic_mapping.json"
$FolderMapping | ConvertTo-Json | Set-Content $mappingPath
Write-Log "Topic mapping saved: $mappingPath"

Write-Host "`n✓ BULK COPY FROM DRIVE COMPLETE" -ForegroundColor Green
Write-Host "  Next: & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\bulk-classify-batches.ps1'" -ForegroundColor Cyan
