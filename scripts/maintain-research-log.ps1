<#
.SYNOPSIS
  Maintain dual-format research logs: narrative essays + structured index.
  Link media IDs to research entries. Auto-generate structured index from narratives.

.DESCRIPTION
  Updates topic-specific research logs:
  - Appends new narrative essay entries (Kroll format)
  - Auto-generates structured JSON index from narratives
  - Links media IDs to entries
  - Extracts facts and Treatment cross-refs
  - Updates research_logs_index.json

.PARAMETER Topic
  Topic number (1-9) to update, or "all" to scan all topics

.PARAMETER Append
  Optional new narrative entry to append (markdown format)

.EXAMPLE
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\maintain-research-log.ps1' -Topic 1
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\maintain-research-log.ps1' -Topic all
#>

param(
  [string]$Topic = "all",
  [string]$Append = ""
)

$RootPath = "C:\CIC_MEDIA_LIBRARY\CIC"
$ResearchLogsPath = "$RootPath\research_logs"
$InventoryFile = "$RootPath\metadata\master_media_inventory.csv"
$LogPath = "$RootPath\logs"
$LogFile = "$LogPath\research_logs_$(Get-Date -Format 'yyyy-MM-dd').log"

$TopicMap = @{
  '1' = @{ name = 'Willow_Run_Bomber_Plant'; file = '1-Willow_Run_log.md'; code = 'WR' }
  '2' = @{ name = 'CESOR_Charles_Emil_Sorensen'; file = '2-CESOR_Biography_log.md'; code = 'CE' }
  '3' = @{ name = 'M_Y_Helene_Yacht'; file = '3-MyHelene_log.md'; code = 'HELENE' }
  '4' = @{ name = 'Harry_Bennett_Service_Department'; file = '4-Harry_Bennett_log.md'; code = 'BENNETT' }
  '5' = @{ name = 'Labor_Relations_1940s'; file = '5-Labor_Relations_log.md'; code = 'LABOR' }
  '6' = @{ name = 'Royal_Correspondence_Denmark'; file = '6-Royal_Correspondence_log.md'; code = 'ROYAL' }
  '7' = @{ name = 'Cuba_Research'; file = '7-Cuba_log.md'; code = 'CUBA' }
  '8' = @{ name = 'Virgin_Islands_Research'; file = '8-Virgin_Islands_log.md'; code = 'VI' }
  '9' = @{ name = 'Willys_Overland_History'; file = '9-Willys_log.md'; code = 'WILLYS' }
}

function Write-Log {
  param([string]$Message)
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$timestamp] $Message" | Add-Content $LogFile
  Write-Host $Message
}

function Load-Inventory {
  if (Test-Path $InventoryFile) {
    return @(Import-Csv -Path $InventoryFile)
  }
  return @()
}

function Extract-FactsFromNarrative {
  param([string]$NarrativeText)

  # Very basic fact extraction (regex-based)
  # In production, use NLP or manual markup
  $facts = @()

  # Look for date patterns (YYYY-MM-DD)
  if ($NarrativeText -match '(\d{4}-\d{2}-\d{2})') {
    $facts += @{
      fact = "Reference to date: $($matches[1])"
      confidence = "medium"
    }
  }

  # Look for numbers that might be measurements
  if ($NarrativeText -match '(\d+(?:,\d{3})+|\d+)\s+(miles|tons|rivets|aircraft|hours|minutes)') {
    $facts += @{
      fact = "Measurement: $($matches[0])"
      confidence = "medium"
    }
  }

  return $facts
}

function Extract-MediaIdsFromNarrative {
  param([string]$NarrativeText, [object[]]$Inventory)

  $mediaIds = @()

  # Look for media IDs in narrative (CIC-XXX-YYYY-ZZZ format)
  $matches = [regex]::Matches($NarrativeText, 'CIC-[A-Z]+-\d+-\d+')
  foreach ($match in $matches) {
    $mediaIds += $match.Value
  }

  return $mediaIds | Select-Object -Unique
}

function Generate-StructuredIndex {
  param(
    [string]$NarrativeText,
    [string]$TopicCode,
    [object[]]$Inventory
  )

  $index = @{
    research_log = "Research Log"
    version = "1.0"
    last_updated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    entries = @()
  }

  # Parse narrative for entries (simplified: look for "## Entry:" patterns)
  $entryPattern = '## Entry:\s*([^\n]+)|^([A-Z]+-\d+)'
  $entryMatches = [regex]::Matches($NarrativeText, $entryPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)

  foreach ($match in $entryMatches) {
    $entryId = if ($match.Groups[2].Value) { $match.Groups[2].Value } else { "Entry-$(Get-Random)" }

    $entry = @{
      entry_id = $entryId
      date_logged = (Get-Date -Format 'yyyy-MM-dd')
      title = "Research Entry"
      key_facts = @(Extract-FactsFromNarrative -NarrativeText $NarrativeText)
      media_evidence = @(Extract-MediaIdsFromNarrative -NarrativeText $NarrativeText -Inventory $Inventory)
      treatment_cross_refs = @()
    }

    $index.entries += $entry
  }

  return $index
}

# MAIN MAINTENANCE LOOP
Write-Log "========== RESEARCH LOG MAINTENANCE START =========="

$inventory = Load-Inventory

$topicsToProcess = if ($Topic -eq "all") { $TopicMap.Keys } else { @($Topic) }

foreach ($topicKey in $topicsToProcess) {
  $topicInfo = $TopicMap[$topicKey]
  if (-not $topicInfo) {
    Write-Log "WARNING: Unknown topic: $topicKey"
    continue
  }

  $logFile = Join-Path $ResearchLogsPath $topicInfo.file
  $indexFile = Join-Path $ResearchLogsPath ($topicInfo.file -replace '\.md$', '_index.json')

  Write-Log "Processing topic: $topicKey — $($topicInfo.name)"

  # Ensure log file exists
  if (-not (Test-Path $logFile)) {
    Write-Log "Creating new log file: $($topicInfo.file)"
    $header = "# $($topicInfo.name.Replace('_', ' ').ToUpper()) — RESEARCH LOG`n`nVersion: 1.0`nLast updated: $(Get-Date -Format 'yyyy-MM-dd')`n`n---`n`n"
    Set-Content -Path $logFile -Value $header
  }

  # Read existing narrative
  $narrative = Get-Content -Path $logFile -Raw

  # If append provided, add it
  if ($Append -and $topicKey -eq $Topic) {
    $Append | Add-Content -Path $logFile
    Write-Log "  ✓ Appended new narrative entry to $($topicInfo.file)"
    $narrative = Get-Content -Path $logFile -Raw
  }

  # Generate/update structured index
  $structuredIndex = Generate-StructuredIndex -NarrativeText $narrative -TopicCode $topicInfo.code -Inventory $inventory
  $structuredIndex | ConvertTo-Json | Set-Content -Path $indexFile

  Write-Log "  ✓ Updated structured index: $($topicInfo.file -replace '\.md$', '_index.json')"

  # Count entries
  $entryCount = $structuredIndex.entries.Count
  Write-Log "  Total entries: $entryCount"
}

Write-Log "========== RESEARCH LOG MAINTENANCE COMPLETE =========="
Write-Log "Research logs updated in: $ResearchLogsPath"
Write-Log "Next step: & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\curate-cic-marketing-assets.ps1'"

Write-Host "`n✓ RESEARCH LOG MAINTENANCE SUCCESS" -ForegroundColor Green
