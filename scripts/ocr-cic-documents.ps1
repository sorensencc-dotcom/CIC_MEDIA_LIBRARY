<#
.SYNOPSIS
  OCR extraction for archival documents. Dual-use: CIC documentary and family history research.

.DESCRIPTION
  Runs OCR on JPEG/PNG/TIFF/PDF files in a directory, extracts structured fields
  (dates, people, places, organizations), detects document type, and writes results
  back to the media sidecar JSON (content_description.ocr_text and extracted_fields).

  Supported OCR engines (in priority order):
    1. Tesseract CLI  — best quality for historical documents; install via:
                         winget install UB-Mannheim.TesseractOCR
                         then add to PATH
    2. Windows.Media.Ocr (WinRT) — built-in fallback, no install required

  Domain modes:
    -Domain documentary  — CIC film pipeline (Ford memos, newspapers, correspondence)
    -Domain genealogy     — Family history pipeline (birth/death/census/deed/military records)

.PARAMETER InputPath
  Directory containing image files and their sidecar JSONs.
  Default: C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified

.PARAMETER Domain
  'documentary' or 'genealogy'. Controls document-type detection taxonomy.
  Default: documentary

.PARAMETER Language
  Tesseract language code (default: eng). Use 'eng+dan' for Danish documents.

.PARAMETER ForceReOCR
  If set, re-OCR files that already have ocr_text in their sidecar.

.EXAMPLE
  # CIC documentary archival batch
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\ocr-cic-documents.ps1' `
    -InputPath 'C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified' `
    -Domain documentary

.EXAMPLE
  # Family history client batch
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\ocr-cic-documents.ps1' `
    -InputPath 'C:\FamilyResearch\Smith_Family\classified' `
    -Domain genealogy `
    -Language eng
#>

param(
  [string]$InputPath  = "C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified",
  [ValidateSet('documentary', 'genealogy')]
  [string]$Domain     = "documentary",
  [string]$Language   = "eng",
  [switch]$ForceReOCR
)

$RootPath  = "C:\CIC_MEDIA_LIBRARY\CIC"
$LogPath   = "$RootPath\logs"
$LogFile   = "$LogPath\ocr_$(Get-Date -Format 'yyyy-MM-dd').log"

if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }

function Write-Log {
  param([string]$Message)
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$ts] $Message" | Add-Content $LogFile
  Write-Host $Message
}

# ---------------------------------------------------------------------------
# ENGINE DETECTION
# ---------------------------------------------------------------------------

function Get-OcrEngine {
  # Prefer Tesseract
  $tess = Get-Command tesseract -ErrorAction SilentlyContinue
  if ($tess) {
    Write-Log "OCR engine: Tesseract ($($tess.Source))"
    return "tesseract"
  }

  # Try WinRT fallback
  try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, ContentType=WindowsRuntime]
    Write-Log "OCR engine: Windows.Media.Ocr (WinRT)"
    return "winrt"
  } catch {
    Write-Log "WARNING: No OCR engine found. Install Tesseract:"
    Write-Log "  winget install UB-Mannheim.TesseractOCR"
    return $null
  }
}

# ---------------------------------------------------------------------------
# TESSERACT OCR
# ---------------------------------------------------------------------------

function Invoke-TesseractOcr {
  param([string]$ImagePath, [string]$Lang)

  $tmpOut = [System.IO.Path]::GetTempFileName()
  $tmpBase = $tmpOut -replace '\.tmp$', ''

  try {
    $proc = Start-Process -FilePath "tesseract" `
      -ArgumentList "`"$ImagePath`"", "`"$tmpBase`"", "-l", $Lang, "txt" `
      -NoNewWindow -Wait -PassThru -RedirectStandardError "$tmpBase.err"

    $txtFile = "$tmpBase.txt"
    if (Test-Path $txtFile) {
      $text = Get-Content $txtFile -Raw -Encoding UTF8
      Remove-Item $txtFile, "$tmpBase.err" -Force -ErrorAction SilentlyContinue
      return $text.Trim(), ($proc.ExitCode -eq 0)
    }
  } catch {
    Write-Log "  Tesseract error: $_"
  } finally {
    Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
  }

  return "", $false
}

# ---------------------------------------------------------------------------
# WINRT OCR
# ---------------------------------------------------------------------------

function Invoke-WinRtOcr {
  param([string]$ImagePath)

  try {
    # Load async helpers
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethod(
      'AsTask', [Type[]]@([Windows.Foundation.IAsyncOperation[Windows.Graphics.Imaging.SoftwareBitmap]])
    )

    $storageFile = [Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath).AsTask().Result
    $stream      = $storageFile.OpenAsync([Windows.Storage.FileAccessMode]::Read).AsTask().Result
    $decoder     = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream).AsTask().Result
    $bitmap      = $decoder.GetSoftwareBitmapAsync().AsTask().Result

    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if (-not $engine) {
      Write-Log "  WinRT: no OCR engine for user profile language"
      return "", $false
    }

    $result = $engine.RecognizeAsync($bitmap).AsTask().Result
    return $result.Text.Trim(), $true
  } catch {
    Write-Log "  WinRT OCR error: $_"
    return "", $false
  }
}

# ---------------------------------------------------------------------------
# FIELD EXTRACTION
# ---------------------------------------------------------------------------

function Extract-Dates {
  param([string]$Text)

  $dates = @()

  # Full dates: January 14, 1943 | Jan 14, 1943 | 14 January 1943
  $monthNames = 'January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec'
  $patterns = @(
    "($monthNames)\s+\d{1,2},?\s+\d{4}",
    "\d{1,2}\s+($monthNames)\s+\d{4}",
    "\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}",
    "\d{4}[\/\-]\d{2}[\/\-]\d{2}"
  )

  foreach ($p in $patterns) {
    $matches = [regex]::Matches($Text, $p, 'IgnoreCase')
    foreach ($m in $matches) {
      if ($dates -notcontains $m.Value) { $dates += $m.Value }
    }
  }

  return $dates
}

function Extract-Names {
  param([string]$Text, [string]$Domain)

  $names = @()

  if ($Domain -eq 'documentary') {
    # CIC-specific named entities
    $knownNames = @(
      'Charles Emil Sorensen', 'Sorensen', 'Harry Bennett', 'Bennett',
      'Henry Ford', 'Edsel Ford', 'Clara Ford', 'King Frederik', 'Frederik X',
      'Roosevelt', 'Albert Kahn'
    )
  } else {
    # Genealogy: look for name patterns near record keywords
    $knownNames = @()
  }

  foreach ($name in $knownNames) {
    if ($Text -match [regex]::Escape($name)) {
      $names += $name
    }
  }

  # General capitalized name pattern (Title Case sequences of 2-3 words)
  $nameMatches = [regex]::Matches($Text, '\b[A-Z][a-z]+\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?\b')
  foreach ($m in $nameMatches) {
    $val = $m.Value
    # Filter obvious false positives
    if ($val -notmatch '^(The|And|For|With|From|This|That|They|Their|There|When|Where|Which|Have|Will|Was|Were|Has|Had|Are|But)\b') {
      if ($names -notcontains $val) { $names += $val }
    }
  }

  return $names | Select-Object -First 20  # cap at 20 to avoid noise
}

function Extract-Places {
  param([string]$Text, [string]$Domain)

  $places = @()

  if ($Domain -eq 'documentary') {
    $knownPlaces = @(
      'Willow Run', 'River Rouge', 'Rouge Plant', 'Dearborn', 'Detroit',
      'Denmark', 'Copenhagen', 'Cuba', 'Virgin Islands', 'St. Croix',
      'Ypsilanti', 'Michigan', 'Washington'
    )
  } else {
    $knownPlaces = @()
  }

  foreach ($place in $knownPlaces) {
    if ($Text -match [regex]::Escape($place)) {
      $places += $place
    }
  }

  # US states and common city patterns
  $statePattern = '\b(Alabama|Alaska|Arizona|Arkansas|California|Colorado|Connecticut|Delaware|Florida|Georgia|Hawaii|Idaho|Illinois|Indiana|Iowa|Kansas|Kentucky|Louisiana|Maine|Maryland|Massachusetts|Michigan|Minnesota|Mississippi|Missouri|Montana|Nebraska|Nevada|New\s+Hampshire|New\s+Jersey|New\s+Mexico|New\s+York|North\s+Carolina|North\s+Dakota|Ohio|Oklahoma|Oregon|Pennsylvania|Rhode\s+Island|South\s+Carolina|South\s+Dakota|Tennessee|Texas|Utah|Vermont|Virginia|Washington|West\s+Virginia|Wisconsin|Wyoming)\b'
  $stateMatches = [regex]::Matches($Text, $statePattern)
  foreach ($m in $stateMatches) {
    if ($places -notcontains $m.Value) { $places += $m.Value }
  }

  return $places
}

function Extract-Organizations {
  param([string]$Text, [string]$Domain)

  $orgs = @()

  if ($Domain -eq 'documentary') {
    $knownOrgs = @(
      'Ford Motor Company', 'Ford Motor', 'UAW', 'United Auto Workers',
      'Willys-Overland', 'Willys Overland', 'Army Air Forces', 'War Production Board',
      'Service Department', 'E&L Transport', 'Benson Ford'
    )
  } else {
    $knownOrgs = @()
  }

  foreach ($org in $knownOrgs) {
    if ($Text -match [regex]::Escape($org)) {
      $orgs += $org
    }
  }

  # Generic company/organization patterns
  $orgMatches = [regex]::Matches($Text, '\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s+(?:Company|Corporation|Corp|Inc|Ltd|County|Church|Bureau|Department|Agency|Board|Commission)\b')
  foreach ($m in $orgMatches) {
    if ($orgs -notcontains $m.Value) { $orgs += $m.Value }
  }

  return $orgs
}

# ---------------------------------------------------------------------------
# DOCUMENT TYPE DETECTION
# ---------------------------------------------------------------------------

$DocumentTypeTaxonomy = @{
  # --- Documentary domain ---
  'Ford_Memo'            = @('memorandum', 'memo', 'inter-office', 'from the desk', 'ford motor')
  'Newspaper_Article'    = @('daily', 'tribune', 'times', 'herald', 'press', 'gazette', 'edition', 'reporter', 'wire service', 'magazine', 'resigns', 'resigned', 'obituary', 'correspondent', 'published')
  'Correspondence'       = @('dear mr', 'dear sir', 'sincerely', 'yours truly', 'respectfully', 'royal palace', 'his majesty')
  'Production_Report'    = @('units produced', 'production schedule', 'assembly', 'shift report', 'output', 'quota')
  'Legal_Document'       = @('whereas', 'hereby', 'agreement', 'contract', 'signed this day', 'witnessed by')

  # --- Genealogy domain ---
  'Birth_Certificate'    = @('certificate of birth', 'born on', 'date of birth', 'place of birth', 'mother', 'father', 'registrar', 'live birth')
  'Death_Certificate'    = @('certificate of death', 'died on', 'date of death', 'cause of death', 'informant', 'burial', 'undertaker')
  'Marriage_Record'      = @('certificate of marriage', 'married on', 'date of marriage', 'husband', 'wife', 'bride', 'groom', 'solemnized')
  'Census_Record'        = @('census', 'enumeration', 'dwelling', 'household', 'enumerator', 'schedule', 'population')
  'Land_Deed'            = @('deed', 'convey', 'grantor', 'grantee', 'parcel', 'lot number', 'acres', 'metes and bounds', 'warranty deed')
  'Probate_Record'       = @('probate', 'last will', 'testament', 'estate of', 'testate', 'intestate', 'executor', 'administrator', 'heirs')
  'Military_Record'      = @('enlisted', 'discharge', 'regiment', 'company', 'service record', 'honorably discharged', 'rank', 'serial number')
  'Immigration_Record'   = @('arrived', 'manifest', 'passenger', 'port of arrival', 'ship', 'last residence', 'alien', 'declaration of intention')
  'Church_Record'        = @('baptized', 'christened', 'confirmation', 'burial', 'parish', 'congregation', 'pastor', 'rector')
  'Naturalization'       = @('declaration of intention', 'petition for naturalization', 'citizen', 'allegiance', 'renounce')
  'Newspaper_Obit'       = @('obituary', 'passed away', 'is survived by', 'funeral services', 'memorial')
}

function Detect-DocumentType {
  param([string]$Text, [string]$Domain)

  $lowerText = $Text.ToLower()
  $scores    = @{}

  foreach ($docType in $DocumentTypeTaxonomy.Keys) {
    # Filter by domain relevance
    if ($Domain -eq 'documentary' -and $docType -match '^(Birth|Death|Marriage|Census|Land|Probate|Military|Immigration|Church|Naturalization)') { continue }
    if ($Domain -eq 'genealogy' -and $docType -match '^(Ford|Production)') { continue }

    $score = 0
    foreach ($keyword in $DocumentTypeTaxonomy[$docType]) {
      if ($lowerText.Contains($keyword)) { $score += 1 }
    }
    if ($score -gt 0) { $scores[$docType] = $score }
  }

  if ($scores.Count -eq 0) { return "Unknown", 0 }

  $best = $scores.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
  return $best.Key, $best.Value
}

# ---------------------------------------------------------------------------
# OCR CONFIDENCE ESTIMATE
# ---------------------------------------------------------------------------

function Estimate-OcrConfidence {
  param([string]$Text)

  if (-not $Text -or $Text.Length -lt 20) { return 0.0 }

  # Heuristic: ratio of word-like tokens to total tokens
  $tokens    = $Text -split '\s+' | Where-Object { $_.Length -gt 0 }
  $wordLike  = $tokens | Where-Object { $_ -match '^[a-zA-Z]{2,}' }
  $ratio     = if ($tokens.Count -gt 0) { $wordLike.Count / $tokens.Count } else { 0 }

  # Penalize if text is very short or full of special chars
  $confidence = [Math]::Round([Math]::Min($ratio, 1.0), 2)
  return $confidence
}

# ---------------------------------------------------------------------------
# MAIN OCR LOOP
# ---------------------------------------------------------------------------

Write-Log "========== OCR PIPELINE START =========="
Write-Log "Domain: $Domain | Language: $Language | InputPath: $InputPath"

$engine = Get-OcrEngine
if (-not $engine) {
  Write-Log "ERROR: No OCR engine available. Exiting."
  exit 1
}

if (-not (Test-Path $InputPath)) {
  Write-Log "ERROR: InputPath does not exist: $InputPath"
  exit 1
}

$imageExtensions = @('*.jpg', '*.jpeg', '*.png', '*.tif', '*.tiff', '*.bmp')
$imageFiles      = @()
foreach ($ext in $imageExtensions) {
  $imageFiles += Get-ChildItem -Path $InputPath -Filter $ext -ErrorAction SilentlyContinue
}

Write-Log "Found $($imageFiles.Count) image files"

$report = @{
  total        = $imageFiles.Count
  ocr_success  = 0
  ocr_skipped  = 0
  ocr_failed   = 0
  needs_review = 0
  engine       = $engine
  domain       = $Domain
  files        = @()
}

foreach ($img in $imageFiles) {
  $sidecarPath = $img.FullName -replace '\.(jpg|jpeg|png|tif|tiff|bmp)$', '.json'
  $sidecar     = $null

  Write-Log "Processing: $($img.Name)"

  # Load or create sidecar
  if (Test-Path $sidecarPath) {
    try { $sidecar = Get-Content $sidecarPath -Raw | ConvertFrom-Json }
    catch { Write-Log "  WARNING: Could not parse sidecar JSON"; $sidecar = $null }
  }

  # Skip if already OCR'd and not forcing
  if (-not $ForceReOCR -and $sidecar -and $sidecar.content_description.ocr_text -and
      $sidecar.content_description.ocr_text.Length -gt 10) {
    Write-Log "  SKIP: already has OCR text (use -ForceReOCR to override)"
    $report.ocr_skipped += 1
    continue
  }

  # Run OCR
  $ocrText  = ""
  $ocrOk    = $false

  if ($engine -eq "tesseract") {
    $ocrText, $ocrOk = Invoke-TesseractOcr -ImagePath $img.FullName -Lang $Language
  } elseif ($engine -eq "winrt") {
    $ocrText, $ocrOk = Invoke-WinRtOcr -ImagePath $img.FullName
  }

  if (-not $ocrOk -or $ocrText.Length -lt 5) {
    Write-Log "  FAILED: OCR produced no usable text"
    $report.ocr_failed += 1
    continue
  }

  Write-Log "  OCR extracted: $($ocrText.Length) chars"

  # Field extraction
  $dates    = Extract-Dates -Text $ocrText
  $names    = Extract-Names -Text $ocrText -Domain $Domain
  $places   = Extract-Places -Text $ocrText -Domain $Domain
  $orgs     = Extract-Organizations -Text $ocrText -Domain $Domain
  $docType, $docTypeScore = Detect-DocumentType -Text $ocrText -Domain $Domain
  $confidence = Estimate-OcrConfidence -Text $ocrText

  Write-Log "  Document type: $docType (score: $docTypeScore) | Confidence: $confidence"
  Write-Log "  Dates: $($dates.Count) | Names: $($names.Count) | Places: $($places.Count)"

  # Build structured OCR result
  $ocrResult = @{
    ocr_engine          = $engine
    ocr_language        = $Language
    ocr_date            = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    ocr_confidence      = $confidence
    needs_manual_review = ($confidence -lt 0.55)
    full_text           = $ocrText
    extracted_fields    = @{
      detected_dates         = $dates
      detected_names         = $names
      detected_places        = $places
      detected_organizations = $orgs
      detected_document_type = $docType
      document_type_score    = $docTypeScore
    }
  }

  # Write back to sidecar
  if ($null -eq $sidecar) {
    # No sidecar exists — create minimal one
    $sidecar = [PSCustomObject]@{
      metadata_version    = "1.0"
      filename            = $img.Name
      domain              = $Domain
      content_description = [PSCustomObject]@{
        short_description = "Pending classification"
        ocr_text          = $ocrText
        ocr_result        = $ocrResult
        entities_identified = @{ people = $names; places = $places; organizations = $orgs }
        keywords          = @()
      }
    }
  } else {
    # Patch existing sidecar
    if (-not $sidecar.content_description) {
      $sidecar | Add-Member -MemberType NoteProperty -Name content_description -Value ([PSCustomObject]@{})
    }
    $sidecar.content_description.ocr_text  = $ocrText
    $sidecar.content_description.ocr_result = $ocrResult

    # Merge extracted entities back into the standard entities_identified block
    if (-not $sidecar.content_description.entities_identified) {
      $sidecar.content_description | Add-Member -MemberType NoteProperty -Name entities_identified -Value ([PSCustomObject]@{
        people        = $names
        places        = $places
        organizations = $orgs
      })
    } else {
      # Merge without overwriting existing manual entries
      $existing = $sidecar.content_description.entities_identified
      $merged = @($existing.people) + @($names) | Sort-Object -Unique
      $existing.people        = @($merged | Select-Object -First 30)
      $existing.places        = @(@($existing.places) + @($places) | Sort-Object -Unique | Select-Object -First 20)
      $existing.organizations = @(@($existing.organizations) + @($orgs) | Sort-Object -Unique | Select-Object -First 20)
    }

    # If document type was detected and classification.type is still Unknown, update it
    if ($docType -ne "Unknown" -and $sidecar.classification -and $sidecar.classification.type -eq "Unknown") {
      $sidecar.classification.type = $docType
    }

    # Add domain field
    if (-not $sidecar.domain) {
      $sidecar | Add-Member -MemberType NoteProperty -Name domain -Value $Domain -Force
    }

    # Flag for manual review
    if (-not $sidecar.usage_flags) {
      $sidecar | Add-Member -MemberType NoteProperty -Name usage_flags -Value ([PSCustomObject]@{})
    }
    $sidecar.usage_flags | Add-Member -MemberType NoteProperty -Name ocr_needs_review -Value $ocrResult.needs_manual_review -Force
  }

  $sidecar | ConvertTo-Json -Depth 10 | Set-Content $sidecarPath -Encoding UTF8
  Write-Log "  ✓ Sidecar updated: $(Split-Path $sidecarPath -Leaf)"

  if ($ocrResult.needs_manual_review) { $report.needs_review += 1 }
  $report.ocr_success += 1
  $report.files += @{
    filename      = $img.Name
    doc_type      = $docType
    confidence    = $confidence
    chars         = $ocrText.Length
    dates_found   = $dates.Count
    names_found   = $names.Count
    needs_review  = $ocrResult.needs_manual_review
  }
}

Write-Log "========== OCR PIPELINE COMPLETE =========="
Write-Log "Success: $($report.ocr_success) | Skipped: $($report.ocr_skipped) | Failed: $($report.ocr_failed) | Needs review: $($report.needs_review)"

$reportPath = "$LogPath\ocr_report_$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
$report | ConvertTo-Json -Depth 10 | Set-Content $reportPath -Encoding UTF8
Write-Log "Report saved: $reportPath"
Write-Log "Next step: & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\classify-cic-media.ps1' -InputPath '$InputPath'"

Write-Host "`n✓ OCR PIPELINE SUCCESS" -ForegroundColor Green
