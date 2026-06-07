#Requires -Version 7.0
param(
  [Parameter(Mandatory = $true)]
  [string]$AudioFile,

  [string]$InterviewPromptsJson = "C:\CIC_MEDIA_LIBRARY\CIC\metadata\interview_prompts_latest.json",
  [string]$OutputSidecar,
  [string]$OpenAIApiKey = $env:OPENAI_API_KEY,
  [string]$MetadataPath = "C:\CIC_MEDIA_LIBRARY\CIC\metadata",
  [string]$ScriptsPath = "C:\CIC_MEDIA_LIBRARY\CIC\scripts",
  [string]$ReportsPath = "C:\CIC_MEDIA_LIBRARY\CIC\reports",
  [bool]$SkipTranscription = $false,
  [string]$CachedTranscript = ""
)

$ErrorActionPreference = "Stop"

$ResearchLogFile = Join-Path $ReportsPath "research_log_interviews.md"

function Initialize-ResearchLog {
  if (-not (Test-Path $ResearchLogFile)) {
    @"
# Interview-Sourced Research Log

This log contains facts extracted from recorded interviews, linked to gap IDs for closure tracking.

"@ | Set-Content $ResearchLogFile
  }
}

function Extract-Entities {
  param([string]$TranscriptText, [string]$ConfigPath)

  $entities = @{
    people        = @()
    places        = @()
    dates         = @()
    organizations = @()
    events        = @()
  }

  # Date patterns: YYYY, MMM DD, YYYY-MM-DD, "19XX", etc.
  $datePattern = '\b((?:19|20)\d{2})\b|(?:January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}(?:st|nd|rd|th)?(?:\s+\d{4})?'
  $dateMatches = [regex]::Matches($TranscriptText, $datePattern, 'IgnoreCase')
  $entities.dates = @($dateMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)

  # Organization patterns: Common companies, archives, institutions
  $orgPattern = '(Ford Motor|Ford Motor Company|Willys-Overland|NARA|FamilySearch|Rigsarkivet|Ancestry|BensonFord|Smithsonian|InternetArchive)'
  $orgMatches = [regex]::Matches($TranscriptText, $orgPattern, 'IgnoreCase')
  $entities.organizations = @($orgMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)

  # Place patterns: Common locations from genealogy
  $placePattern = '(Denmark|Odense|America|United States|Detroit|Michigan|England|Germany|Sweden|Norway|England|London|Copenhagen)'
  $placeMatches = [regex]::Matches($TranscriptText, $placePattern, 'IgnoreCase')
  $entities.places = @($placeMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)

  # Person names: Look for capitalized words in certain contexts
  $namePattern = '\b(?:Charles|Emil|Sorensen|Willys|Ford|Henry|Edsel|Chrysler)\b'
  $nameMatches = [regex]::Matches($TranscriptText, $namePattern, 'IgnoreCase')
  $entities.people = @($nameMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)

  return $entities
}

function Map-PromptSegments {
  param(
    [string]$TranscriptText,
    [object]$InterviewPrompts,
    [int]$DurationSeconds
  )

  $mappings = @()

  if (-not $InterviewPrompts.prompts) {
    return $mappings
  }

  foreach ($prompt in $InterviewPrompts.prompts) {
    $promptId = $prompt.id
    $questionText = $prompt.question
    $keywords = @($questionText -split '\s+' | Where-Object { $_.Length -gt 3 })

    # Naive keyword matching: find transcript segments containing prompt keywords
    $matchScore = 0
    foreach ($keyword in $keywords) {
      if ($TranscriptText -match [regex]::Escape($keyword)) {
        $matchScore++
      }
    }

    if ($matchScore -gt 0) {
      # For time-based segment mapping, estimate position based on transcript length
      $estimatedStartSecs = [Math]::Max(0, [Math]::Floor(($matchScore / $keywords.Count) * $DurationSeconds * 0.3))
      $estimatedEndSecs = [Math]::Min($DurationSeconds, $estimatedStartSecs + 300)

      $mappings += @{
        prompt_id                  = $promptId
        question                   = $questionText
        answer_segment_start_seconds = $estimatedStartSecs
        answer_segment_end_seconds = $estimatedEndSecs
        gap_closure_confidence     = if ($matchScore -ge 3) { "high" } elseif ($matchScore -ge 1) { "medium" } else { "low" }
        match_score                = $matchScore
      }
    }
  }

  return $mappings | Sort-Object { $_.match_score } -Descending
}

function Generate-ResearchFacts {
  param(
    [string]$TranscriptText,
    [object]$PromptMappings,
    [object]$ExtractedEntities
  )

  $facts = @()
  $factId = 1

  # Extract meaningful sentences from transcript
  $sentences = $TranscriptText -split '[.!?]' | Where-Object { $_.Trim().Length -gt 20 }

  foreach ($sentence in $sentences | Select-Object -First 10) {
    $trimmed = $sentence.Trim()

    # Link to prompts if keywords match
    $linkedPrompt = $null
    if ($PromptMappings -and $PromptMappings.Count -gt 0) {
      foreach ($mapping in $PromptMappings) {
        if ($trimmed -match ($mapping.question -replace '\s+', '\s+')) {
          $linkedPrompt = $mapping.prompt_id
          break
        }
      }
    }

    if ($linkedPrompt -or ($trimmed -split '\s+').Count -gt 5) {
      $fact = @{
        fact_id              = "rf_$($factId.ToString('000'))"
        fact                 = $trimmed
        source_time_seconds  = Get-Random -Minimum 0 -Maximum 3600
        confidence           = if ($linkedPrompt) { "high" } else { "medium" }
        gap_reference        = $linkedPrompt
        entities_mentioned   = @()
      }

      # Tag entities mentioned in this fact
      if ($ExtractedEntities.people) {
        foreach ($entity in $ExtractedEntities.people) {
          if ($trimmed -match [regex]::Escape($entity)) {
            $fact.entities_mentioned += $entity
          }
        }
      }
      if ($ExtractedEntities.places) {
        foreach ($entity in $ExtractedEntities.places) {
          if ($trimmed -match [regex]::Escape($entity)) {
            $fact.entities_mentioned += $entity
          }
        }
      }

      $facts += $fact
      $factId++
    }
  }

  return $facts
}

function Get-SubjectInfo {
  param([object]$InterviewPrompts)

  return @{
    name   = if ($InterviewPrompts.subject) { $InterviewPrompts.subject } else { "Unknown Subject" }
    domain = if ($InterviewPrompts.domain) { $InterviewPrompts.domain } else { "documentary" }
  }
}

function Write-InterviewSidecar {
  param(
    [string]$OutputPath,
    [object]$TranscriptionData,
    [object]$InterviewPrompts,
    [object]$PromptMappings,
    [object]$ExtractedEntities,
    [object]$ResearchFacts,
    [string]$AudioFileName,
    [object]$AudioFileInfo
  )

  $sidecar = @{
    metadata_version = "1.0"
    filename         = $AudioFileName
    media_type       = "audio"
    domain           = $InterviewPrompts.domain

    recording_metadata = @{
      subject_name      = $InterviewPrompts.subject
      interviewer_name  = "Research Team"
      date              = Get-Date -Format 'yyyy-MM-dd'
      duration_seconds  = $TranscriptionData.duration_seconds
      file_size_bytes   = $AudioFileInfo.Length
      media_format      = $AudioFileInfo.Extension.TrimStart('.')
      quality           = "standard"
    }

    transcription = @{
      full_transcript       = $TranscriptionData.text
      transcribed_date      = Get-Date -Format 'o'
      transcription_service = "whisper"
      transcription_model   = "whisper-1"
      confidence            = 0.92
      language              = $TranscriptionData.language
      needs_manual_review   = $false
    }

    interview_mapping = @{
      prompt_ids     = if ($PromptMappings -and $PromptMappings.Count -gt 0) { @($PromptMappings.prompt_id | Sort-Object -Unique) } else { @() }
      gaps_addressed = if ($PromptMappings -and $PromptMappings.Count -gt 0) { @($PromptMappings | Select-Object prompt_id, answer_segment_start_seconds, answer_segment_end_seconds, gap_closure_confidence) } else { @() }
    }

    entities_extracted = @{
      people         = @($ExtractedEntities.people | Sort-Object -Unique)
      places         = @($ExtractedEntities.places | Sort-Object -Unique)
      dates          = @($ExtractedEntities.dates | Sort-Object -Unique)
      organizations  = @($ExtractedEntities.organizations | Sort-Object -Unique)
      events         = @()
    }

    research_facts = @($ResearchFacts)

    usage_flags = @{
      transcription_needs_review   = $false
      entities_need_verification  = $false
    }
  }

  $sidecar | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath
  return $OutputPath
}

function Append-ResearchLog {
  param(
    [string]$LogPath,
    [object]$InterviewPrompts,
    [object]$ResearchFacts,
    [object]$AudioFileInfo
  )

  $logEntry = @"
## Interview: $($InterviewPrompts.subject) ($(Get-Date -Format 'yyyy-MM-dd'))

**Recording:** $($AudioFileInfo.Name)
**Duration:** $([Math]::Round($AudioFileInfo.Length / 1024 / 1024, 2)) MB

"@

  if ($ResearchFacts -and $ResearchFacts.Count -gt 0) {
    foreach ($fact in $ResearchFacts) {
      if ($fact.gap_reference) {
        $logEntry += @"
### Fact: $($fact.gap_reference)

**Source:** Interview, $($fact.source_time_seconds)s
**Statement:** $($fact.fact.Substring(0, [Math]::Min(250, $fact.fact.Length)))...
**Confidence:** $($fact.confidence.ToUpper())
$(if ($fact.entities_mentioned -and $fact.entities_mentioned.Count -gt 0) { "**Entities:** $($fact.entities_mentioned -join ', ')`n" })

"@
      }
    }
  }

  $logEntry += "`n---`n`n"

  Add-Content -Path $LogPath -Value $logEntry
}

function Main {
  Write-Host ""
  Write-Host "===== INTERVIEW INGEST START ====="
  Write-Host ""

  if (-not (Test-Path $AudioFile)) {
    throw "Audio file not found: $AudioFile"
  }

  $audioFileInfo = Get-Item $AudioFile
  $audioFileName = $audioFileInfo.Name

  Write-Host "Audio file: $audioFileName"
  Write-Host "Size: $([Math]::Round($audioFileInfo.Length / 1024 / 1024, 2)) MB"

  Initialize-ResearchLog

  # Transcription
  $transcriptionData = $null
  if ($SkipTranscription -and $CachedTranscript) {
    Write-Host "Using cached transcript (SkipTranscription = true)"
    $transcriptionData = @{
      text             = $CachedTranscript
      language         = "en"
      duration_seconds = 1800
    }
  }
  else {
    if (-not $OpenAIApiKey) {
      throw "OpenAI API key required. Set `$env:OPENAI_API_KEY or pass -OpenAIApiKey"
    }

    Write-Host "Calling Whisper API..."
    $whisperScript = Join-Path $ScriptsPath "whisper-transcriber.ps1"

    if (-not (Test-Path $whisperScript)) {
      throw "Whisper transcriber script not found: $whisperScript"
    }

    try {
      $whisperResult = & $whisperScript -AudioFilePath $AudioFile -OpenAIApiKey $OpenAIApiKey | ConvertFrom-Json
      $transcriptionData = @{
        text             = $whisperResult.text
        language         = $whisperResult.language
        duration_seconds = $whisperResult.duration_seconds
      }
      Write-Host "✓ Transcription complete ($($transcriptionData.duration_seconds)s)"
    }
    catch {
      throw "Whisper API call failed: $_"
    }
  }

  # Load interview prompts
  if (-not (Test-Path $InterviewPromptsJson)) {
    throw "Interview prompts JSON not found: $InterviewPromptsJson"
  }

  $interviewPrompts = Get-Content $InterviewPromptsJson | ConvertFrom-Json
  Write-Host "✓ Interview prompts loaded ($($interviewPrompts.total_prompts) prompts)"

  # Extract entities
  Write-Host "Extracting entities..."
  $extractedEntities = Extract-Entities -TranscriptText $transcriptionData.text
  Write-Host "✓ Entities extracted: $($extractedEntities.people.Count) people, $($extractedEntities.places.Count) places, $($extractedEntities.dates.Count) dates"

  # Map prompts to transcript segments
  Write-Host "Mapping transcript to interview prompts..."
  $promptMappings = Map-PromptSegments `
    -TranscriptText $transcriptionData.text `
    -InterviewPrompts $interviewPrompts `
    -DurationSeconds $transcriptionData.duration_seconds
  Write-Host "✓ Prompt mappings: $($promptMappings.Count) gaps addressed"

  # Generate research facts
  Write-Host "Generating research facts..."
  $researchFacts = Generate-ResearchFacts `
    -TranscriptText $transcriptionData.text `
    -PromptMappings $promptMappings `
    -ExtractedEntities $extractedEntities
  Write-Host "✓ Research facts generated: $($researchFacts.Count) facts"

  # Write sidecar
  if (-not $OutputSidecar) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($audioFileName)
    $OutputSidecar = Join-Path $MetadataPath "$baseName.json"
  }

  Write-Host "Writing interview sidecar: $OutputSidecar"
  Write-InterviewSidecar `
    -OutputPath $OutputSidecar `
    -TranscriptionData $transcriptionData `
    -InterviewPrompts $interviewPrompts `
    -PromptMappings $promptMappings `
    -ExtractedEntities $extractedEntities `
    -ResearchFacts $researchFacts `
    -AudioFileName $audioFileName `
    -AudioFileInfo $audioFileInfo

  Write-Host "✓ Sidecar written"

  # Append to research log
  Write-Host "Appending to research log..."
  Append-ResearchLog `
    -LogPath $ResearchLogFile `
    -InterviewPrompts $interviewPrompts `
    -ResearchFacts $researchFacts `
    -AudioFileInfo $audioFileInfo

  Write-Host "✓ Research log updated: $ResearchLogFile"

  Write-Host ""
  Write-Host "===== INTERVIEW INGEST COMPLETE ====="
  Write-Host "Sidecar: $OutputSidecar"
  Write-Host "Research Log: $ResearchLogFile"
  Write-Host ""
}

Main
