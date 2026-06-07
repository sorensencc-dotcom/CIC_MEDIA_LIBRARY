#Requires -Version 7.0
param(
  [string]$GapsMarkdown = "C:\CIC_MEDIA_LIBRARY\CIC\reports\report_gaps_latest.md",
  [string]$EntityGraph = "C:\CIC_MEDIA_LIBRARY\CIC\metadata\entity_graph.json",
  [string]$Config = "C:\CIC_MEDIA_LIBRARY\CIC\metadata\genealogy_config.json",
  [string]$Domain = "documentary",
  [string]$OutputJson = "C:\CIC_MEDIA_LIBRARY\CIC\metadata\interview_prompts_latest.json",
  [string]$OutputMarkdown = "C:\CIC_MEDIA_LIBRARY\CIC\metadata\interview_prompts_latest.md"
)

$ErrorActionPreference = "Stop"

function Get-GapsFromMarkdown {
  param([string]$MarkdownPath)

  if (-not (Test-Path $MarkdownPath)) {
    throw "Gaps markdown file not found: $MarkdownPath"
  }

  $content = Get-Content $MarkdownPath -Raw
  $gaps = @()

  $lines = $content -split "`n"
  $i = 0
  while ($i -lt $lines.Count) {
    $line = $lines[$i].Trim()

    if ($line -match "^## No documents found: (.+)$") {
      $entity = $matches[1]
      $i++

      $priority = "Medium"
      $recommendation = ""
      $gap_description = $entity

      while ($i -lt $lines.Count) {
        $line = $lines[$i].Trim()

        if ($line -match "\*\*Priority:\*\*\s+(.+?)\s+\|") {
          $priority = $matches[1]
        }
        if ($line -match "^Search .+|^Contact .+|^Add .+") {
          $recommendation = $line
          $i++
          break
        }
        if ($line -match "^##") { break }

        $i++
      }

      $gaps += @{
        entity           = $entity
        gap_description  = "No documents found: $gap_description"
        priority         = $priority
        recommendation   = $recommendation
        gap_type         = "content"
      }
      continue
    }

    if ($line -match "^## Credentialed connectors not yet active: (.+)$") {
      $entity = $matches[1]
      $i++

      $priority = "Medium"
      $recommendation = ""

      while ($i -lt $lines.Count) {
        $line = $lines[$i].Trim()

        if ($line -match "\*\*Priority:\*\*\s+(.+?)\s+\|") {
          $priority = $matches[1]
        }
        if ($line -match "^Add .+") {
          $recommendation = $line
          $i++
          break
        }
        if ($line -match "^##") { break }

        $i++
      }

      $gaps += @{
        entity           = $entity
        gap_description  = "Credentialed connectors not yet active: $entity"
        priority         = $priority
        recommendation   = $recommendation
        gap_type         = "archive_coverage"
      }
      continue
    }

    $i++
  }

  return $gaps
}

function Get-EntityContext {
  param([string]$EntityGraph, [string]$Subject)

  if (-not (Test-Path $EntityGraph)) {
    return @{ persons = @(); places = @(); dates = @() }
  }

  try {
    $graph = Get-Content $EntityGraph | ConvertFrom-Json

    $persons = @()
    $places = @()
    $dates = @()

    if ($graph.nodes) {
      $persons = $graph.nodes | Where-Object { $_.type -eq "person" } | Select-Object -ExpandProperty label
      $places = $graph.nodes | Where-Object { $_.type -eq "place" } | Select-Object -ExpandProperty label
      $dates = $graph.nodes | Where-Object { $_.type -eq "event" } | Select-Object -ExpandProperty date | Where-Object { $_ }
    }

    return @{
      persons = $persons
      places  = $places
      dates   = $dates
    }
  }
  catch {
    Write-Warning "Could not parse entity graph: $_"
    return @{ persons = @(); places = @(); dates = @() }
  }
}

function Convert-GapToPrompt {
  param(
    [hashtable]$Gap,
    [hashtable]$EntityContext,
    [string]$Domain
  )

  $promptId = "gap_$($Gap.gap_type)_$($Gap.entity -replace '\s+', '_' -replace '[^\w_]', '' | ForEach-Object { $_.ToLower() })"

  $priorityOrder = @{ "High" = 1; "Medium" = 2; "Low" = 3 }
  $priorityRank = $priorityOrder[$Gap.priority] ?? 3

  if ($Gap.gap_type -eq "content") {
    $question = "Tell us about $($Gap.entity)."

    if ($Gap.entity -match "(\d{4})\D+(\d{4})") {
      $startYear = $matches[1]
      $endYear = $matches[2]
      $cleanEntity = $Gap.entity -replace "\s*\(\d{4}.*?\)", ""
      $question = "Tell us about the period from $startYear to $endYear in $cleanEntity."
    }

    if ($Domain -eq "genealogy" -and $Gap.entity -match "early life|birth|childhood") {
      $question = "Tell us about your early life and family. Where were you born? What were your parents' names?"
    }
    elseif ($Domain -eq "documentary" -and $Gap.entity -match "early|birth|childhood") {
      $question = "What can you tell us about your childhood and early career?"
    }

    $followUps = @(
      "What do you remember most vividly from this period?",
      "Who were the key people in your life during this time?",
      "Do you have any documents or photos from this period that might help researchers?"
    )

    $answerType = "oral_history"
    $timeEstimate = 15
  }
  elseif ($Gap.gap_type -eq "archive_coverage") {
    $question = "[SYSTEM ACTION] Activate archive connector: $($Gap.entity)"
    $followUps = @()
    $answerType = "system_action"
    $timeEstimate = 0
  }
  else {
    $question = "Can you tell us more about $($Gap.entity)?"
    $followUps = @("Any other details?")
    $answerType = "oral_history"
    $timeEstimate = 5
  }

  return @{
    id                = $promptId
    priority          = $Gap.priority
    priority_rank     = $priorityRank
    gap_type          = $Gap.gap_type
    entity            = $Gap.entity
    question          = $question
    follow_ups        = $followUps
    answer_type       = $answerType
    time_estimate_minutes = $timeEstimate
    metadata          = @{
      gap_source       = $Gap.gap_description
      recommendation   = $Gap.recommendation
      related_entities = @()
      archive_backup   = ""
    }
  }
}

function Rank-InterviewPrompts {
  param([array]$Prompts)

  return $Prompts | Sort-Object @(
    @{ Expression = "priority_rank"; Ascending = $true },
    @{ Expression = { if ($_.gap_type -eq "content") { 0 } else { 1 } }; Ascending = $true },
    @{ Expression = "entity"; Ascending = $true }
  )
}

function Format-InterviewGuide {
  param([array]$Prompts, [string]$Subject, [string]$Domain)

  $output = @"
# Interview Guide — $Subject ($Domain)

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

**Total Questions:** $($Prompts | Where-Object { $_.gap_type -ne "archive_coverage" }).Count
**Estimated Time:** $(($Prompts | Where-Object { $_.gap_type -ne "archive_coverage" } | Measure-Object -Property time_estimate_minutes -Sum).Sum) minutes

---

## Priority Questions

"@

  $highPriority = $Prompts | Where-Object { $_.priority -eq "High" }
  foreach ($prompt in $highPriority) {
    if ($prompt.gap_type -ne "archive_coverage") {
      $output += "`n### Q: $($prompt.entity)`n"
      $output += "`n**Prompt:** $($prompt.question)`n"
      if ($prompt.follow_ups.Count -gt 0) {
        $output += "`n**Follow-ups:**`n"
        foreach ($fu in $prompt.follow_ups) {
          $output += "- $fu`n"
        }
      }
      $output += "`n**Expected:** $($prompt.answer_type) (~$($prompt.time_estimate_minutes) min)`n"
    }
  }

  $output += "`n## System Actions`n"
  $actions = $Prompts | Where-Object { $_.gap_type -eq "archive_coverage" }
  if ($actions.Count -gt 0) {
    foreach ($action in $actions) {
      $output += "`n- **$($action.entity)**: $($action.metadata.recommendation)`n"
    }
  }
  else {
    $output += "`nNo system actions required.`n"
  }

  return $output
}

Write-Host "===== GAP-TO-INTERVIEW-PROMPTS START ====="
Write-Host "Reading gaps from: $GapsMarkdown"

try {
  $gaps = Get-GapsFromMarkdown -MarkdownPath $GapsMarkdown
  Write-Host "✓ Parsed $($gaps.Count) gaps"

  $entityContext = Get-EntityContext -EntityGraph $EntityGraph -Subject "CIC Subject"
  Write-Host "✓ Loaded entity context: $($entityContext.persons.Count) persons, $($entityContext.places.Count) places"

  $prompts = @()
  foreach ($gap in $gaps) {
    $prompt = Convert-GapToPrompt -Gap $gap -EntityContext $entityContext -Domain $Domain
    $prompts += $prompt
  }

  $prompts = Rank-InterviewPrompts -Prompts $prompts
  Write-Host "✓ Ranked $($prompts.Count) prompts"

  $guideText = Format-InterviewGuide -Prompts $prompts -Subject "Charles Emil Sorensen" -Domain $Domain

  $output = @{
    generated      = Get-Date -Format 'o'
    domain         = $Domain
    subject        = "Charles Emil Sorensen"
    total_prompts  = ($prompts | Where-Object { $_.gap_type -ne "archive_coverage" }).Count
    total_gaps     = $gaps.Count
    prompts        = $prompts
    guide_markdown = $guideText
  }

  $output | ConvertTo-Json -Depth 10 | Set-Content $OutputJson
  Write-Host "✓ Written JSON: $OutputJson"

  $guideText | Set-Content $OutputMarkdown
  Write-Host "✓ Written Guide: $OutputMarkdown"

  Write-Host ""
  Write-Host $guideText

  Write-Host "===== GAP-TO-INTERVIEW-PROMPTS COMPLETE ====="
  Write-Host "Interview prompts queued: $($output.total_prompts)"
}
catch {
  Write-Error "Error in gap-to-interview-prompts: $_"
  exit 1
}
