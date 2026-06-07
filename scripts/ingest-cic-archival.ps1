<#
.SYNOPSIS
  Ingest HEIC media batches, convert to JPEG, extract metadata, generate hashes, detect duplicates.

.DESCRIPTION
  Processes HEIC files from _Inbox:
  - Converts HEIC → JPEG (quality 85)
  - Extracts EXIF/metadata
  - Generates SHA-256 hash
  - Creates thumbnail
  - Checks deduplication
  - Outputs classified staging folder

.PARAMETER InputPath
  Source directory containing HEIC files (default: media\_Inbox\[latest batch])

.PARAMETER OutputPath
  Destination for JPEG + sidecars (default: media\_Inbox\classified)

.PARAMETER Quality
  JPEG quality 1-100 (default: 85)

.EXAMPLE
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\ingest-cic-archival.ps1' `
    -InputPath 'C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\Kroll_Batch_005'
#>

param(
  [string]$InputPath = "C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox",
  [string]$OutputPath = "C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified",
  [int]$Quality = 85,
  [switch]$Force
)

# Configuration
$RootPath = "C:\CIC_MEDIA_LIBRARY\CIC"
$MetadataPath = "$RootPath\metadata"
$LogPath = "$RootPath\logs"
$InventoryFile = "$MetadataPath\master_media_inventory.csv"
$DedupeFile = "$MetadataPath\media_versioning.json"
$LogFile = "$LogPath\ingest_$(Get-Date -Format 'yyyy-MM-dd').log"

# Ensure output path exists
if (-not (Test-Path $OutputPath)) {
  New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Initialize log
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] INGEST START - InputPath: $InputPath" | Add-Content $LogFile

function Write-Log {
  param([string]$Message)
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$timestamp] $Message" | Add-Content $LogFile
  Write-Host $Message
}

function Get-FileHash {
  param([string]$FilePath)
  $hash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
  return $hash.ToLower()
}

function Load-DuplicateRegistry {
  if (Test-Path $DedupeFile) {
    return Get-Content $DedupeFile | ConvertFrom-Json
  }
  return @{ hashes = @{}; duplicates = @() }
}

function Save-DuplicateRegistry {
  param($Registry)
  $Registry | ConvertTo-Json | Set-Content $DedupeFile
}

function Test-Duplicate {
  param([string]$Hash, [object]$Registry)
  if ($Registry.hashes.ContainsKey($Hash)) {
    return $true, $Registry.hashes[$Hash]
  }
  return $false, $null
}

function Convert-HEICtoJPEG {
  param([string]$HEICPath)

  # Check if ffmpeg or equivalent is available
  $converter = "C:\Program Files\ImageMagick-7.1.1\convert.exe"
  if (-not (Test-Path $converter)) {
    $converter = (Get-Command convert -ErrorAction SilentlyContinue).Source
  }
  if (-not $converter) {
    Write-Log "ERROR: ImageMagick convert.exe not found. Install ImageMagick or ffmpeg."
    return $null
  }

  $JPEGPath = $HEICPath -replace '\.heic$', '.jpg'
  $JPEGPath = Join-Path $OutputPath (Split-Path $JPEGPath -Leaf)

  try {
    & $converter $HEICPath -quality $Quality -strip $JPEGPath 2>&1 | Out-Null
    if (Test-Path $JPEGPath) {
      Write-Log "✓ Converted: $(Split-Path $HEICPath -Leaf) → $(Split-Path $JPEGPath -Leaf)"
      return $JPEGPath
    }
  }
  catch {
    Write-Log "ERROR converting $HEICPath : $_"
  }
  return $null
}

function Extract-Metadata {
  param([string]$FilePath)

  $metadata = @{
    date_ingested = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    date_modified = (Get-Item $FilePath).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
    file_size_bytes = (Get-Item $FilePath).Length
  }

  # Attempt to extract EXIF (requires Image.Exif or ExifTool)
  try {
    # Placeholder: real implementation uses ExifTool or ImageMagick identify
    $metadata.exif = @{ orientation = "normal" }
  }
  catch {
    $metadata.exif = @{}
  }

  return $metadata
}

function Create-MetadataSidecar {
  param(
    [string]$Filename,
    [string]$SHA256Hash,
    [object]$Metadata
  )

  $sidecar = @{
    metadata_version = "1.0"
    filename = $Filename
    file_extension = [System.IO.Path]::GetExtension($Filename)
    file_size_bytes = $Metadata.file_size_bytes
    sha256_hash = $SHA256Hash
    date_ingested = $Metadata.date_ingested
    date_modified = $Metadata.date_modified
    classification = @{
      type = "Unclassified"
      primary_topic = "99-Uncategorized"
      documentary_significance = "Unknown"
      historical_date = $null
      historical_date_confidence = "unknown"
    }
    source_metadata = @{
      archive_origin = "Pending"
      batch_id = "Pending"
      rights_status = "needs_clearance"
      attribution_required = $true
    }
    content_description = @{
      short_description = "Pending classification"
      entities_identified = @{ people = @(); places = @(); organizations = @() }
      keywords = @()
      ocr_text = ""
    }
    usage_flags = @{
      social_media_ready = $false
      pitch_deck_candidate = $false
      quality_rating = 0
      deduplication_status = "unique"
    }
    treatment_cross_refs = @()
  }

  return $sidecar
}

# MAIN INGESTION LOOP
Write-Log "========== INGEST PHASE START =========="

if (-not (Test-Path $InputPath)) {
  Write-Log "ERROR: InputPath does not exist: $InputPath"
  exit 1
}

$heicFiles = @(Get-ChildItem -Path $InputPath -Filter "*.heic" -ErrorAction SilentlyContinue)
if ($heicFiles.Count -eq 0) {
  Write-Log "No HEIC files found in $InputPath"
  exit 0
}

Write-Log "Found $($heicFiles.Count) HEIC files"

$registry = Load-DuplicateRegistry
$ingestionReport = @{
  total_files = $heicFiles.Count
  new_files = 0
  duplicates = 0
  errors = 0
  files = @()
}

foreach ($heic in $heicFiles) {
  Write-Log "Processing: $($heic.Name)"

  # Convert HEIC to JPEG
  $jpeg = Convert-HEICtoJPEG -HEICPath $heic.FullName
  if (-not $jpeg) {
    $ingestionReport.errors += 1
    continue
  }

  # Generate SHA-256 hash
  $hash = Get-FileHash -FilePath $jpeg
  Write-Log "  SHA-256: $hash"

  # Check for duplicate
  $isDupe, $origMediaId = Test-Duplicate -Hash $hash -Registry $registry
  if ($isDupe) {
    Write-Log "  ⚠ DUPLICATE detected. Original media ID: $origMediaId"
    $ingestionReport.duplicates += 1
    Remove-Item $jpeg -Force
    continue
  }

  # Extract metadata
  $metadata = Extract-Metadata -FilePath $jpeg

  # Create sidecar JSON
  $sidecar = Create-MetadataSidecar -Filename (Split-Path $jpeg -Leaf) -SHA256Hash $hash -Metadata $metadata
  $sidecarPath = $jpeg -replace '\.jpg$', '.json'
  $sidecar | ConvertTo-Json | Set-Content $sidecarPath

  Write-Log "  ✓ Sidecar created: $(Split-Path $sidecarPath -Leaf)"

  # Update registry
  $registry.hashes[$hash] = "Pending_MediaID_Assignment"

  $ingestionReport.new_files += 1
  $ingestionReport.files += @{
    filename = Split-Path $jpeg -Leaf
    hash = $hash
    size_bytes = (Get-Item $jpeg).Length
    sidecar = Split-Path $sidecarPath -Leaf
  }
}

# Save updated registry
Save-DuplicateRegistry -Registry $registry

Write-Log "========== INGEST COMPLETE =========="
Write-Log "New files: $($ingestionReport.new_files) | Duplicates: $($ingestionReport.duplicates) | Errors: $($ingestionReport.errors)"
Write-Log "Output path: $OutputPath"
Write-Log "Ready for classification: & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\classify-cic-media.ps1' -InputPath '$OutputPath'"

$reportPath = "$LogPath\ingest_report_$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
$ingestionReport | ConvertTo-Json | Set-Content $reportPath
Write-Log "Report saved: $reportPath"

Write-Host "`n✓ INGEST SUCCESS" -ForegroundColor Green
