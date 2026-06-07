<#
.SYNOPSIS
  Classify ingested media: type, topic, significance, entities, keywords, Treatment cross-refs.

.DESCRIPTION
  Enriches media metadata sidecars with:
  - Content type (Photo | Document | Newspaper | Map | Diagram | Video | Audio | Correspondence)
  - Topic routing:
      documentary — CIC topics (1-Willow Run, 2-CESOR, 3-Helene, etc.)
      genealogy   — family lines from config file (e.g., 1-Smith_Paternal, 2-Johnson_Maternal)
  - Significance scoring (domain-aware)
  - Entity extraction (people, places, organizations)
  - Keyword generation
  - Historical date inference (filename + OCR-detected dates)
  - Treatment / Narrative section cross-ref suggestions
  - OCR-aware: uses Phase 50 OCR results when present to improve type detection

.PARAMETER InputPath
  Directory containing media + sidecar JSONs.
  Default: C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified

.PARAMETER Domain
  'documentary' (default) or 'genealogy'. Controls taxonomy, routing, and significance scoring.

.PARAMETER ConfigFile
  Path to genealogy_config.json defining family surnames, lines, date ranges, geographic focus.
  Only used when -Domain genealogy. A template is created at $RootPath\metadata\genealogy_config.json
  if none is provided.

.PARAMETER MetadataOverride
  Optional CSV or JSON with pre-defined topic assignments (batch classification override).

.EXAMPLE
  # CIC documentary batch (default — unchanged from v1)
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\classify-cic-media.ps1' `
    -InputPath 'C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified'

.EXAMPLE
  # Family history client batch
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\classify-cic-media.ps1' `
    -InputPath 'C:\FamilyResearch\Smith_Family\classified' `
    -Domain genealogy `
    -ConfigFile 'C:\FamilyResearch\Smith_Family\genealogy_config.json'
#>

param(
  [string]$InputPath       = "C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified",
  [ValidateSet('documentary', 'genealogy')]
  [string]$Domain          = "documentary",
  [string]$ConfigFile      = "",
  [string]$MetadataOverride = ""
)

$RootPath = "C:\CIC_MEDIA_LIBRARY\CIC"
$LogPath  = "$RootPath\logs"
$LogFile  = "$LogPath\classification_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log {
  param([string]$Message)
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$timestamp] $Message" | Add-Content $LogFile
  Write-Host $Message
}

Write-Log "========== CLASSIFICATION START =========="
Write-Log "Domain: $Domain | InputPath: $InputPath"

# ---------------------------------------------------------------------------
# DOCUMENTARY TAXONOMY (unchanged from v1)
# ---------------------------------------------------------------------------

$DocTypeRules_Documentary = @{
  'Photograph'     = @('photo', 'img', 'picture', 'kd_truck', 'riveting', 'workforce', 'factory')
  'Document'       = @('memo', 'letter', 'report', 'form', '.pdf', 'documentation', 'archive')
  'Newspaper'      = @('newspaper', 'newspaper_', 'times', 'herald', 'journal', 'front_page', 'article', 'magazine', 'fortune')
  'Map'            = @('map', 'route', 'diagram', 'chart')
  'Correspondence' = @('letter', 'correspondence', 'king', 'royal', 'response')
}

$TopicRouting_Documentary = @{
  '1-Willow_Run_Bomber_Plant'          = @('willow', 'wr-', 'bomber', 'b24', 'kd_', 'riveting', 'aircraft')
  '2-CESOR_Charles_Emil_Sorensen'      = @('sorensen', 'cesor', 'charles', 'departure', 'resignation', 'willys')
  '3-M_Y_Helene_Yacht'                 = @('helene', 'yacht', 'boat', 'dock', 'hull')
  '4-Harry_Bennett_Service_Department' = @('bennett', 'service', 'e&l_', 'e_and_l')
  '5-Labor_Relations_1940s'            = @('labor', 'uaw', 'strike', 'workforce', 'worker')
  '6-Royal_Correspondence_Denmark'     = @('king', 'royal', 'frederik', 'denmark', 'letter')
  '7-Cuba_Research'                    = @('cuba', 'cuban')
  '8-Virgin_Islands_Research'          = @('virgin_islands', 'usvi', 'st_croix')
  '9-Willys_Overland_History'          = @('willys', 'jeep', 'overland')
}

$TreatmentMapping = @{
  'The Engineering Mind'         = @('riveting', 'precision', 'tolerance', 'mechanize', 'automatic', 'women', 'workforce', 'production')
  'The Parallel Power Structure' = @('bennett', 'service', 'e&l_', 'organized', 'loyalty', 'kd_', 'logistics', 'transport')
  'The Pivot & Decline'          = @('fortune', 'roosevelt', 'decline', 'departure', 'resignation', 'march_1944', '1944', 'sidelining')
  'The Royal Dimension'          = @('king', 'royal', 'frederik', 'correspondence', 'denmark', 'letter')
}

# Significance: type → score (documentary)
$Significance_Documentary = @{
  'Newspaper'         = 'High'
  'Newspaper_Article' = 'High'
  'Document'          = 'High'
  'Ford_Memo'         = 'High'
  'Legal_Document'    = 'High'
  'Correspondence'    = 'High'
  'Production_Report' = 'High'
  'Map'               = 'Medium'
  'Photograph'        = 'Medium'
  'Unknown'           = 'Low'
}

# ---------------------------------------------------------------------------
# GENEALOGY TAXONOMY
# ---------------------------------------------------------------------------

$DocTypeRules_Genealogy = @{
  'Birth_Certificate'    = @('birth', 'born', 'certificate of birth', 'live birth', 'birth record')
  'Death_Certificate'    = @('death', 'died', 'certificate of death', 'cause of death', 'burial')
  'Marriage_Record'      = @('marriage', 'married', 'bride', 'groom', 'husband', 'wife', 'wedding', 'solemnized')
  'Census_Record'        = @('census', 'enumeration', 'dwelling', 'household', 'enumerator')
  'Land_Deed'            = @('deed', 'convey', 'grantor', 'grantee', 'parcel', 'acres', 'warranty')
  'Probate_Record'       = @('probate', 'will', 'estate', 'testate', 'intestate', 'executor', 'heirs')
  'Military_Record'      = @('enlisted', 'discharge', 'regiment', 'service record', 'honorably', 'rank', 'serial')
  'Immigration_Record'   = @('arrived', 'manifest', 'passenger', 'port of arrival', 'ship', 'alien', 'declaration')
  'Church_Record'        = @('baptized', 'christened', 'confirmation', 'parish', 'congregation', 'pastor')
  'Naturalization'       = @('naturalization', 'citizenship', 'allegiance', 'renounce', 'petition for')
  'Newspaper_Obituary'   = @('obituary', 'passed away', 'survived by', 'funeral', 'memorial')
  'Photograph'           = @('photo', 'portrait', 'img', 'picture', 'snapshot')
  'Correspondence'       = @('letter', 'dear', 'sincerely', 'yours truly')
}

# Significance tiers for genealogy (vital records outrank all others)
$Significance_Genealogy = @{
  'Birth_Certificate'  = 'High'
  'Death_Certificate'  = 'High'
  'Marriage_Record'    = 'High'
  'Naturalization'     = 'High'
  'Military_Record'    = 'High'
  'Immigration_Record' = 'High'
  'Probate_Record'     = 'Medium'
  'Land_Deed'          = 'Medium'
  'Census_Record'      = 'Medium'
  'Church_Record'      = 'Medium'
  'Newspaper_Obituary' = 'Medium'
  'Correspondence'     = 'Medium'
  'Photograph'         = 'Low'
  'Unknown'            = 'Low'
}

# ---------------------------------------------------------------------------
# GENEALOGY CONFIG LOADER
# ---------------------------------------------------------------------------

$GenealogyConfig = $null
$GenealogyTopicRouting = @{}
$GenealogyNarrativeSections = @{}

function Load-GenealogyConfig {
  param([string]$CfgPath)

  $defaultCfgPath = "$RootPath\metadata\genealogy_config.json"

  if (-not $CfgPath -or -not (Test-Path $CfgPath)) {
    if (Test-Path $defaultCfgPath) {
      $CfgPath = $defaultCfgPath
      Write-Log "Using default genealogy config: $defaultCfgPath"
    } else {
      # Write a template config for the user to fill in
      $template = @{
        client_name  = "Client Family Name"
        date_range   = @{ earliest = 1800; latest = 1980 }
        geography    = @("United States", "Europe")
        family_lines = @(
          @{
            line_id    = "1-Paternal_Line"
            surnames   = @("Smith", "Smyth")
            keywords   = @("smith", "smyth")
            narrative  = "Paternal Line"
          },
          @{
            line_id    = "2-Maternal_Line"
            surnames   = @("Johnson", "Johnston")
            keywords   = @("johnson", "johnston")
            narrative  = "Maternal Line"
          }
        )
        narrative_sections = @(
          @{ section = "Immigration Journey";   keywords = @("arrived", "ship", "port", "passenger", "immigrant") },
          @{ section = "Military Service";      keywords = @("enlisted", "discharge", "regiment", "war", "service") },
          @{ section = "Land & Property";       keywords = @("deed", "parcel", "acres", "lot", "property") },
          @{ section = "Vital Records";         keywords = @("born", "died", "married", "birth", "death", "marriage") },
          @{ section = "Community & Religion";  keywords = @("church", "parish", "baptized", "congregation", "pastor") }
        )
      }
      $template | ConvertTo-Json -Depth 5 | Set-Content $defaultCfgPath -Encoding UTF8
      Write-Log "Created genealogy config template: $defaultCfgPath — edit surnames/family lines before use"
      $CfgPath = $defaultCfgPath
    }
  }

  try {
    $cfg = Get-Content $CfgPath -Raw | ConvertFrom-Json
    Write-Log "Loaded genealogy config: $($cfg.client_name) | $($cfg.family_lines.Count) lines"
    return $cfg
  } catch {
    Write-Log "ERROR: Could not parse genealogy config at $CfgPath — $_"
    return $null
  }
}

function Build-GenealogyTopicRouting {
  param($Config)
  $routing = @{}
  foreach ($line in $Config.family_lines) {
    $routing[$line.line_id] = $line.keywords
  }
  return $routing
}

function Build-GenealogyNarrativeSections {
  param($Config)
  $sections = @{}
  foreach ($sec in $Config.narrative_sections) {
    $sections[$sec.section] = $sec.keywords
  }
  return $sections
}

# ---------------------------------------------------------------------------
# SHARED FUNCTIONS
# ---------------------------------------------------------------------------

function Detect-ContentType {
  param([string]$Filename, [string]$OcrType = "")

  # If OCR already detected a high-confidence type, honour it
  if ($OcrType -and $OcrType -ne "Unknown" -and $OcrType -ne "") {
    return $OcrType, "ocr"
  }

  $lower = $Filename.ToLower()
  $rules = if ($Domain -eq 'genealogy') { $DocTypeRules_Genealogy } else { $DocTypeRules_Documentary }

  foreach ($type in $rules.Keys) {
    foreach ($keyword in $rules[$type]) {
      if ($lower.Contains($keyword)) { return $type, "filename" }
    }
  }

  return "Unknown", "none"
}

function Route-Topic {
  param([string]$Filename, [string]$OcrText = "")

  $combined = ($Filename + " " + $OcrText).ToLower()
  $routing  = if ($Domain -eq 'genealogy') { $GenealogyTopicRouting } else { $TopicRouting_Documentary }

  foreach ($topic in $routing.Keys) {
    foreach ($keyword in $routing[$topic]) {
      if ($combined.Contains($keyword)) { return $topic }
    }
  }

  return "99-Uncategorized"
}

function Score-Significance {
  param([string]$ContentType)

  $table = if ($Domain -eq 'genealogy') { $Significance_Genealogy } else { $Significance_Documentary }
  if ($table.ContainsKey($ContentType)) { return $table[$ContentType] }
  return 'Low'
}

function Suggest-NarrativeCrossRefs {
  param([string]$Filename, [string]$Description, [string]$OcrText = "")

  $text = ($Filename + " " + $Description + " " + $OcrText).ToLower()
  $refs = @()

  $mapping = if ($Domain -eq 'genealogy') { $GenealogyNarrativeSections } else { $TreatmentMapping }

  foreach ($section in $mapping.Keys) {
    $score = 0
    foreach ($keyword in $mapping[$section]) {
      if ($text.Contains($keyword)) { $score += 1 }
    }
    if ($score -gt 0) {
      $refs += @{
        section   = $section
        relevance = if ($score -ge 3) { "high" } elseif ($score -ge 1) { "medium" } else { "low" }
      }
    }
  }

  return $refs | Sort-Object -Property @{Expression={ $_.relevance }; Descending=$true}
}

function Extract-Entities {
  param([string]$Filename, [object]$ExistingEntities = $null)

  $entities = @{
    people        = @()
    places        = @()
    organizations = @()
  }

  # Carry forward OCR-extracted entities if present
  if ($ExistingEntities) {
    if ($ExistingEntities.people)        { $entities.people        = @($ExistingEntities.people) }
    if ($ExistingEntities.places)        { $entities.places        = @($ExistingEntities.places) }
    if ($ExistingEntities.organizations) { $entities.organizations = @($ExistingEntities.organizations) }
  }

  $lower = $Filename.ToLower()

  if ($Domain -eq 'documentary') {
    if ($lower.Contains("sorensen") -or $lower.Contains("cesor")) { $entities.people        += "Charles Emil Sorensen" }
    if ($lower.Contains("bennett"))                               { $entities.people        += "Harry Bennett" }
    if ($lower.Contains("king") -or $lower.Contains("frederik")) { $entities.people        += "King Frederik X" }
    if ($lower.Contains("willow"))                                { $entities.places        += "Willow Run" }
    if ($lower.Contains("detroit"))                               { $entities.places        += "Detroit" }
    if ($lower.Contains("rouge"))                                 { $entities.places        += "Rouge Plant" }
    if ($lower.Contains("cuba"))                                  { $entities.places        += "Cuba" }
    if ($lower.Contains("virgin_islands") -or $lower.Contains("usvi")) { $entities.places  += "US Virgin Islands" }
    if ($lower.Contains("ford"))                                  { $entities.organizations += "Ford Motor Company" }
    if ($lower.Contains("uaw"))                                   { $entities.organizations += "UAW" }
    if ($lower.Contains("willys") -or $lower.Contains("jeep"))   { $entities.organizations += "Willys-Overland" }
  } elseif ($Domain -eq 'genealogy' -and $GenealogyConfig) {
    foreach ($line in $GenealogyConfig.family_lines) {
      foreach ($surname in $line.surnames) {
        if ($lower.Contains($surname.ToLower())) {
          $entities.people += $surname
        }
      }
    }
    foreach ($geo in $GenealogyConfig.geography) {
      if ($lower.Contains($geo.ToLower())) {
        $entities.places += $geo
      }
    }
  }

  # Deduplicate
  $entities.people        = @($entities.people        | Sort-Object -Unique)
  $entities.places        = @($entities.places        | Sort-Object -Unique)
  $entities.organizations = @($entities.organizations | Sort-Object -Unique)

  return $entities
}

function Infer-HistoricalDate {
  param([string]$Filename, [array]$OcrDates = @())

  # Prefer OCR-detected dates
  if ($OcrDates -and $OcrDates.Count -gt 0) {
    return @{
      year       = $null
      confidence = "ocr"
      formatted  = $OcrDates[0]
      all_dates  = $OcrDates
    }
  }

  # Fall back to filename year
  if ($Filename -match '(\d{4})') {
    $year = [int]$matches[1]
    $minYear = if ($Domain -eq 'genealogy') { 1700 } else { 1900 }
    if ($year -ge $minYear -and $year -le (Get-Date).Year) {
      return @{
        year       = $year
        confidence = "estimated"
        formatted  = "$year-01-01"
        all_dates  = @("$year-01-01")
      }
    }
  }

  return @{ year = $null; confidence = "unknown"; formatted = $null; all_dates = @() }
}

# ---------------------------------------------------------------------------
# LOAD GENEALOGY CONFIG (if applicable)
# ---------------------------------------------------------------------------

if ($Domain -eq 'genealogy') {
  $GenealogyConfig         = Load-GenealogyConfig -CfgPath $ConfigFile
  if ($GenealogyConfig) {
    $GenealogyTopicRouting       = Build-GenealogyTopicRouting -Config $GenealogyConfig
    $GenealogyNarrativeSections  = Build-GenealogyNarrativeSections -Config $GenealogyConfig
  }
}

# ---------------------------------------------------------------------------
# MAIN CLASSIFICATION LOOP
# ---------------------------------------------------------------------------

Write-Log "Classifying media from: $InputPath"

if (-not (Test-Path $InputPath)) {
  Write-Log "ERROR: InputPath does not exist: $InputPath"
  exit 1
}

$sidecars = @(Get-ChildItem -Path $InputPath -Filter "*.json" -ErrorAction SilentlyContinue)
Write-Log "Found $($sidecars.Count) sidecar files"

$classificationReport = @{
  domain     = $Domain
  total      = $sidecars.Count
  classified = 0
  errors     = 0
  files      = @()
}

foreach ($sidecar in $sidecars) {

  try {
    $json = Get-Content $sidecar.FullName -Raw | ConvertFrom-Json
  } catch {
    Write-Log "ERROR: Could not parse $($sidecar.Name) — $_"
    $classificationReport.errors += 1
    continue
  }

  $filename = $json.filename
  if (-not $filename) { $filename = $sidecar.BaseName }

  Write-Log "Classifying: $filename"

  # Pull OCR data if Phase 50 has already run
  $ocrType  = ""
  $ocrText  = ""
  $ocrDates = @()
  if ($json.content_description) {
    if ($json.content_description.ocr_result) {
      $ocrR     = $json.content_description.ocr_result
      $ocrType  = $ocrR.extracted_fields.detected_document_type
      $ocrDates = @($ocrR.extracted_fields.detected_dates)
    }
    if ($json.content_description.ocr_text) {
      $ocrText = $json.content_description.ocr_text
    }
  }

  # Ensure classification block exists
  if (-not $json.classification) {
    $json | Add-Member -MemberType NoteProperty -Name classification -Value ([PSCustomObject]@{
      type                       = "Unclassified"
      primary_topic              = "99-Uncategorized"
      documentary_significance   = "Unknown"
      historical_date            = $null
      historical_date_confidence = "unknown"
    }) -Force
  }

  # Detect content type — OCR result takes priority over filename
  $contentType, $typeSource = Detect-ContentType -Filename $filename -OcrType $ocrType
  $json.classification.type = $contentType

  # Route to topic — uses OCR full text for richer keyword matching
  $topic = Route-Topic -Filename $filename -OcrText $ocrText
  $json.classification.primary_topic = $topic

  # Infer historical date
  $dateInfo = Infer-HistoricalDate -Filename $filename -OcrDates $ocrDates
  if ($dateInfo.formatted) {
    $json.classification.historical_date            = $dateInfo.formatted
    $json.classification.historical_date_confidence = $dateInfo.confidence
  }
  if ($dateInfo.all_dates -and $dateInfo.all_dates.Count -gt 1) {
    $json.classification | Add-Member -MemberType NoteProperty -Name all_detected_dates -Value $dateInfo.all_dates -Force
  }

  # Extract / merge entities
  $existingEntities = if ($json.content_description) { $json.content_description.entities_identified } else { $null }
  $entities = Extract-Entities -Filename $filename -ExistingEntities $existingEntities
  if ($json.content_description) {
    $json.content_description.entities_identified = $entities
  }

  # Generate keywords from filename tokens + OCR top words
  $filenameTokens = @($filename.Split('_') | Where-Object { $_.Length -gt 3 })
  $json.content_description.keywords = $filenameTokens

  # Narrative / Treatment cross-refs
  $description = if ($json.content_description.short_description) { $json.content_description.short_description } else { "" }
  $refs = Suggest-NarrativeCrossRefs -Filename $filename -Description $description -OcrText $ocrText
  if ($refs.Count -gt 0) {
    if ($Domain -eq 'genealogy') {
      $json | Add-Member -MemberType NoteProperty -Name narrative_cross_refs -Value $refs -Force
    } else {
      $json | Add-Member -MemberType NoteProperty -Name treatment_cross_refs -Value $refs -Force
    }
  }

  # Significance scoring
  $significance = Score-Significance -ContentType $contentType
  $json.classification.documentary_significance = $significance

  # Stamp domain
  $json | Add-Member -MemberType NoteProperty -Name domain -Value $Domain -Force

  # Save
  $json | ConvertTo-Json -Depth 10 | Set-Content $sidecar.FullName -Encoding UTF8

  $typeNote = if ($typeSource -eq 'ocr') { "$contentType (via OCR)" } else { $contentType }
  Write-Log "  ✓ $typeNote | Topic: $topic | Significance: $significance"

  $classificationReport.classified += 1
  $classificationReport.files += @{
    filename     = $filename
    type         = $contentType
    type_source  = $typeSource
    topic        = $topic
    significance = $significance
  }
}

Write-Log "========== CLASSIFICATION COMPLETE =========="
Write-Log "Classified: $($classificationReport.classified) | Errors: $($classificationReport.errors)"
Write-Log "Next step: & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\organize-cic-media-library.ps1'"

$reportPath = "$LogPath\classification_report_$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
$classificationReport | ConvertTo-Json -Depth 5 | Set-Content $reportPath -Encoding UTF8
Write-Log "Report saved: $reportPath"

Write-Host "`n✓ CLASSIFICATION SUCCESS" -ForegroundColor Green
