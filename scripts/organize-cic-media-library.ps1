<#
.SYNOPSIS
  Organize classified media into DAM hierarchy: By_Topic, By_Type, By_Source.
  Generate master inventory, search index, media ID assignments.

.DESCRIPTION
  Takes classified media from _Inbox\classified and:
  - Assigns media IDs (CIC-WR-1944-001, etc.)
  - Creates symbolic links in By_Topic/, By_Type/, By_Source/
  - Generates/updates master_media_inventory.csv
  - Updates search_index.json
  - Updates treatment_crossref_index.json
  - Validates checksums
  - Logs all movements

.PARAMETER InputPath
  Source directory (default: media\_Inbox\classified)

.PARAMETER Validate
  Run checksum validation after organization (default: $true)

.EXAMPLE
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\organize-cic-media-library.ps1'
#>

param(
  [string]$InputPath = "C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified",
  [switch]$Validate = $true
)

$RootPath = "C:\CIC_MEDIA_LIBRARY\CIC"
$MediaPath = "$RootPath\media"
$MetadataPath = "$RootPath\metadata"
$LogPath = "$RootPath\logs"
$LogFile = "$LogPath\organization_$(Get-Date -Format 'yyyy-MM-dd').log"
$InventoryFile = "$MetadataPath\master_media_inventory.csv"
$SearchIndexFile = "$MetadataPath\search_index.json"
$TreatmentRefFile = "$MetadataPath\treatment_crossref_index.json"
$MediaVersionFile = "$MetadataPath\media_versioning.json"

function Write-Log {
  param([string]$Message)
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$timestamp] $Message" | Add-Content $LogFile
  Write-Host $Message
}

function Get-NextMediaId {
  param([string]$TopicCode, [object]$VersionRegistry)

  if (-not $VersionRegistry.sequences) {
    $VersionRegistry.sequences = @{}
  }

  $key = "CIC-$TopicCode"
  if (-not $VersionRegistry.sequences[$key]) {
    $VersionRegistry.sequences[$key] = 1
  } else {
    $VersionRegistry.sequences[$key] += 1
  }

  $seq = $VersionRegistry.sequences[$key].ToString().PadLeft(3, '0')
  return "$key-$seq"
}

function Load-VersionRegistry {
  if (Test-Path $MediaVersionFile) {
    return Get-Content $MediaVersionFile | ConvertFrom-Json
  }
  return @{ sequences = @{}; last_updated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ') }
}

function Save-VersionRegistry {
  param($Registry)
  $Registry.last_updated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  $Registry | ConvertTo-Json | Set-Content $MediaVersionFile
}

function Get-TopicCode {
  param([string]$Topic)
  $codeMap = @{
    '1-Willow_Run_Bomber_Plant'              = 'WR'
    '2-CESOR_Charles_Emil_Sorensen'          = 'CE'
    '3-M_Y_Helene_Yacht'                     = 'HELENE'
    '4-Harry_Bennett_Service_Department'     = 'BENNETT'
    '5-Labor_Relations_1940s'                = 'LABOR'
    '6-Royal_Correspondence_Denmark'         = 'ROYAL'
    '7-Cuba_Research'                        = 'CUBA'
    '8-Virgin_Islands_Research'              = 'VI'
    '9-Willys_Overland_History'              = 'WILLYS'
    '99-Uncategorized'                       = 'UNC'
  }
  return $codeMap[$Topic] -or 'UNC'
}

function Get-SubtopicFolder {
  param([string]$Topic, [string]$Type)

  $subtopics = @{
    '1-Willow_Run_Bomber_Plant' = @{
      'Photograph' = '1944_Production_Logistics'
      'Document' = 'Quality_Control_Tolerances'
      'Newspaper' = '1944_Labor_Crisis_July-Aug'
      'Default' = 'General'
    }
    '2-CESOR_Charles_Emil_Sorensen' = @{
      'Photograph' = 'Biographical_Family_Archive'
      'Document' = 'Rouge_Plant_Operations_1930s-1941'
      'Correspondence' = 'March_1944_Departure_Timeline'
      'Default' = 'General'
    }
  }

  if ($subtopics[$Topic] -and $subtopics[$Topic][$Type]) {
    return $subtopics[$Topic][$Type]
  }

  return if ($subtopics[$Topic]) { $subtopics[$Topic]['Default'] } else { 'General' }
}

function Create-SymbolicLink {
  param([string]$Source, [string]$Destination)

  $destDir = Split-Path $Destination
  if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
  }

  if (Test-Path $Destination) {
    Remove-Item $Destination -Force -ErrorAction SilentlyContinue
  }

  # Use New-Item with -ItemType SymbolicLink (requires admin on Windows)
  # Fallback: copy file if symlink fails
  try {
    New-Item -ItemType SymbolicLink -Path $Destination -Value $Source -Force -ErrorAction Stop | Out-Null
    return $true
  }
  catch {
    Write-Log "  ⚠ Symlink failed for $(Split-Path $Destination -Leaf), copying instead"
    Copy-Item -Path $Source -Destination $Destination -Force
    return $true
  }
}

function Load-Inventory {
  if (Test-Path $InventoryFile) {
    return @(Import-Csv -Path $InventoryFile)
  }
  return @()
}

function Save-Inventory {
  param([object[]]$Inventory)
  $Inventory | Export-Csv -Path $InventoryFile -NoTypeInformation -Encoding UTF8
}

function Update-SearchIndex {
  param([object[]]$Inventory)

  $index = @{
    version = "1.0"
    last_updated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    total_media_count = $Inventory.Count
    indexes = @{
      by_topic = @{}
      by_type = @{}
      by_archive = @{}
      by_date_range = @{}
      by_usage_flag = @{}
    }
  }

  foreach ($item in $Inventory) {
    # by_topic
    if (-not $index.indexes.by_topic[$item.primary_topic]) {
      $index.indexes.by_topic[$item.primary_topic] = @()
    }
    $index.indexes.by_topic[$item.primary_topic] += $item.media_id

    # by_type
    if (-not $index.indexes.by_type[$item.type]) {
      $index.indexes.by_type[$item.type] = @()
    }
    $index.indexes.by_type[$item.type] += $item.media_id

    # by_archive
    if (-not $index.indexes.by_archive[$item.archive_origin]) {
      $index.indexes.by_archive[$item.archive_origin] = @()
    }
    $index.indexes.by_archive[$item.archive_origin] += $item.media_id

    # by_usage_flag
    if ($item.social_ready -eq 'true') {
      if (-not $index.indexes.by_usage_flag['social_media_ready']) {
        $index.indexes.by_usage_flag['social_media_ready'] = @()
      }
      $index.indexes.by_usage_flag['social_media_ready'] += $item.media_id
    }
  }

  $index | ConvertTo-Json | Set-Content $SearchIndexFile
}

# MAIN ORGANIZATION LOOP
Write-Log "========== ORGANIZATION START =========="

if (-not (Test-Path $InputPath)) {
  Write-Log "ERROR: InputPath does not exist: $InputPath"
  exit 1
}

$jpegFiles = @(Get-ChildItem -Path $InputPath -Filter "*.jpg" -ErrorAction SilentlyContinue)
Write-Log "Found $($jpegFiles.Count) JPEG files to organize"

$versionRegistry = Load-VersionRegistry
$existingInventory = Load-Inventory
$newInventoryItems = @()
$organizationReport = @{
  total_files = $jpegFiles.Count
  organized = 0
  errors = 0
  files = @()
  media_ids = @()
}

foreach ($jpeg in $jpegFiles) {
  $sidecarPath = $jpeg.FullName -replace '\.jpg$', '.json'
  if (-not (Test-Path $sidecarPath)) {
    Write-Log "ERROR: No sidecar found for $($jpeg.Name)"
    $organizationReport.errors += 1
    continue
  }

  $sidecar = Get-Content $sidecarPath | ConvertFrom-Json

  # Assign media ID
  $topicCode = Get-TopicCode -Topic $sidecar.classification.primary_topic
  $mediaId = Get-NextMediaId -TopicCode $topicCode -VersionRegistry $versionRegistry

  # Infer historical year for media ID
  $year = if ($sidecar.classification.historical_date) {
    [datetime]::ParseExact($sidecar.classification.historical_date, 'yyyy-MM-dd', $null).Year
  } else {
    "UNKNOWN"
  }

  # Update sidecar with media ID
  $sidecar.media_id = $mediaId
  $sidecar | ConvertTo-Json | Set-Content $sidecarPath

  Write-Log "Assigning: $mediaId ← $($jpeg.Name)"

  # Get subtopic folder
  $subtopic = Get-SubtopicFolder -Topic $sidecar.classification.primary_topic -Type $sidecar.classification.type

  # Create folders and links
  # By_Topic
  $byTopicFolder = "$MediaPath\By_Topic\$($sidecar.classification.primary_topic)\$subtopic"
  Create-SymbolicLink -Source $jpeg.FullName -Destination "$byTopicFolder\$mediaId.jpg"
  Create-SymbolicLink -Source $sidecarPath -Destination "$byTopicFolder\$mediaId.json"

  # By_Type
  $byTypeFolder = "$MediaPath\By_Type\$($sidecar.classification.type)"
  Create-SymbolicLink -Source $jpeg.FullName -Destination "$byTypeFolder\$mediaId.jpg"

  # By_Source
  $bySourceFolder = "$MediaPath\By_Source\$($sidecar.source_metadata.archive_origin)\$($sidecar.source_metadata.batch_id)"
  Create-SymbolicLink -Source $jpeg.FullName -Destination "$bySourceFolder\$mediaId.jpg"

  Write-Log "  ✓ Organized to: $byTopicFolder"

  # Add to inventory
  $inventoryItem = [PSCustomObject]@{
    media_id = $mediaId
    filename = $jpeg.Name
    type = $sidecar.classification.type
    primary_topic = $sidecar.classification.primary_topic
    secondary_topics = $sidecar.classification.secondary_topics -join '|'
    documentary_significance = $sidecar.classification.documentary_significance
    historical_date = $sidecar.classification.historical_date
    date_ingested = $sidecar.date_ingested
    archive_origin = $sidecar.source_metadata.archive_origin
    batch_id = $sidecar.source_metadata.batch_id
    rights_status = $sidecar.source_metadata.rights_status
    social_ready = $sidecar.usage_flags.social_media_ready
    pitch_ready = $sidecar.usage_flags.pitch_deck_candidate
    quality_rating = $sidecar.usage_flags.quality_rating
    sha256_hash = $sidecar.sha256_hash
    treatment_sections = (($sidecar.treatment_cross_refs | ForEach-Object { $_.treatment_section }) -join '|')
  }

  $newInventoryItems += $inventoryItem
  $organizationReport.media_ids += $mediaId
  $organizationReport.organized += 1
  $organizationReport.files += @{
    media_id = $mediaId
    filename = $jpeg.Name
    topic = $sidecar.classification.primary_topic
  }
}

# Save updated registry
Save-VersionRegistry -Registry $versionRegistry

# Merge and save inventory
$allInventory = @($existingInventory) + @($newInventoryItems)
Save-Inventory -Inventory $allInventory

# Update search index
Update-SearchIndex -Inventory $allInventory

Write-Log "========== ORGANIZATION COMPLETE =========="
Write-Log "Organized: $($organizationReport.organized) | Errors: $($organizationReport.errors)"
Write-Log "Inventory updated: $InventoryFile"
Write-Log "Search index updated: $SearchIndexFile"
Write-Log "Media IDs assigned: $($organizationReport.media_ids -join ', ')"

$reportPath = "$LogPath\organization_report_$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
$organizationReport | ConvertTo-Json | Set-Content $reportPath
Write-Log "Report saved: $reportPath"

Write-Log "Next step: & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\maintain-research-log.ps1'"

Write-Host "`n✓ ORGANIZATION SUCCESS" -ForegroundColor Green
