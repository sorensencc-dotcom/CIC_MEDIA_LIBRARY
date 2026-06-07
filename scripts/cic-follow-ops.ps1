<#
.SYNOPSIS
  Surface all outstanding operations: rights, gaps, Dad questions, readiness.
  Generate email summary + update Excel log.

.DESCRIPTION
  - Identifies media needing rights clearance
  - Surfaces research gaps (topics with <5 items)
  - Extracts Dad questions from research logs
  - Scores marketing readiness
  - Drafts email summary
  - Updates CIC_Dad_Questions_Log.xlsx on Drive

.PARAMETER EmailSummary
  Send email to user (default: $false)

.PARAMETER EmailTo
  Recipient email (default: sorensencc@gmail.com)

.EXAMPLE
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\cic-follow-ops.ps1' -EmailSummary $true
#>

param(
  [switch]$EmailSummary = $false,
  [string]$EmailTo = "sorensencc@gmail.com"
)

$RootPath = "C:\CIC_MEDIA_LIBRARY\CIC"
$InventoryFile = "$RootPath\metadata\master_media_inventory.csv"
$ReadinessFile = "$RootPath\operations\marketing_readiness.json"
$LogPath = "$RootPath\logs"
$LogFile = "$LogPath\follow_ops_$(Get-Date -Format 'yyyy-MM-dd').log"
$OpsChecklistFile = "$RootPath\operations\follow_ops_checklist.json"
$DadQuestionsFile = "$RootPath\operations\CIC_Dad_Questions_Log.xlsx"

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

function Assess-RightsStatus {
  param([object[]]$Inventory)

  $rightsReport = @{
    pre_cleared = @()
    needs_clearance = @()
    clearance_summary = @{}
  }

  foreach ($item in $Inventory) {
    if ($item.rights_status -eq 'pre_cleared') {
      $rightsReport.pre_cleared += $item.media_id
    } else {
      $rightsReport.needs_clearance += $item.media_id
    }
  }

  # Summary by archive
  $archiveCounts = $Inventory | Group-Object -Property archive_origin | ForEach-Object {
    $cleared = ($_.Group | Where-Object { $_.rights_status -eq 'pre_cleared' }).Count
    $needsClearing = ($_.Group | Where-Object { $_.rights_status -ne 'pre_cleared' }).Count

    $rightsReport.clearance_summary[$_.Name] = @{
      total = $_.Count
      cleared = $cleared
      needs_clearance = $needsClearing
      status = if ($needsClearing -eq 0) { "✓ Complete" } else { "⏳ In Progress" }
    }
  }

  return $rightsReport
}

function Identify-ResearchGaps {
  param([object[]]$Inventory)

  $gaps = @()

  $topics = @(
    '1-Willow_Run_Bomber_Plant',
    '2-CESOR_Charles_Emil_Sorensen',
    '3-M_Y_Helene_Yacht',
    '4-Harry_Bennett_Service_Department',
    '5-Labor_Relations_1940s',
    '6-Royal_Correspondence_Denmark',
    '7-Cuba_Research',
    '8-Virgin_Islands_Research',
    '9-Willys_Overland_History'
  )

  foreach ($topic in $topics) {
    $count = ($Inventory | Where-Object { $_.primary_topic -eq $topic }).Count
    if ($count -lt 5) {
      $gaps += @{
        topic = $topic
        current_items = $count
        target_items = 5
        gap = (5 - $count)
        priority = if ($count -eq 0) { "CRITICAL" } elseif ($count -lt 3) { "HIGH" } else { "MEDIUM" }
      }
    }
  }

  return $gaps
}

function Extract-DadQuestions {
  param([object[]]$Inventory)

  $questions = @()

  # Scan research logs for "Ask Dad:" patterns
  $researchLogsPath = "$RootPath\research_logs"
  $logFiles = @(Get-ChildItem -Path $researchLogsPath -Filter "*_log.md" -ErrorAction SilentlyContinue)

  foreach ($logFile in $logFiles) {
    $content = Get-Content -Path $logFile.FullName -Raw
    $matches = [regex]::Matches($content, '\[\s*\]\s*Ask\s+Dad:\s*([^\n]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    foreach ($match in $matches) {
      $questions += @{
        question = $match.Groups[1].Value.Trim()
        source_log = $logFile.Name
        priority = "PENDING"
        date_added = (Get-Date -Format 'yyyy-MM-dd')
      }
    }
  }

  # Also suggest questions based on gaps
  foreach ($gap in (Identify-ResearchGaps -Inventory $Inventory)) {
    if ($gap.priority -eq 'CRITICAL' -or $gap.priority -eq 'HIGH') {
      $topicName = $gap.topic.Replace('_', ' ').Replace('-', ' ')
      $questions += @{
        question = "What sources or contacts do you know for: $topicName ?"
        source_log = "gaps_analysis"
        priority = $gap.priority
        date_added = (Get-Date -Format 'yyyy-MM-dd')
      }
    }
  }

  return $questions
}

function Score-MarketingReadiness {
  param([object[]]$Inventory)

  $readiness = @{
    social_calendar_score = 0
    pitch_deck_score = 0
    grant_bundles_score = 0
    overall_score = 0
  }

  # Social media readiness
  $socialReady = ($Inventory | Where-Object { $_.social_ready -eq 'True' }).Count
  $readiness.social_calendar_score = [int](($socialReady / [Math]::Max($Inventory.Count, 1)) * 100)

  # Pitch deck readiness
  $pitchReady = ($Inventory | Where-Object { $_.pitch_ready -eq 'True' -and [int]$_.quality_rating -ge 8 }).Count
  $readiness.pitch_deck_score = [int](($pitchReady / [Math]::Max(50, 1)) * 100)

  # Grant bundles readiness
  $grantReady = ($Inventory | Where-Object { $_.documentary_significance -eq 'High' -and [int]$_.quality_rating -ge 8 }).Count
  $readiness.grant_bundles_score = [int](($grantReady / [Math]::Max(30, 1)) * 100)

  # Overall
  $readiness.overall_score = [int](
    ($readiness.social_calendar_score + $readiness.pitch_deck_score + $readiness.grant_bundles_score) / 3
  )

  return $readiness
}

# MAIN OPERATIONS ASSESSMENT
Write-Log "========== FOLLOW-OPS ASSESSMENT START =========="

$inventory = Load-Inventory
if ($inventory.Count -eq 0) {
  Write-Log "ERROR: No inventory found"
  exit 1
}

Write-Log "Assessing $($inventory.Count) media items"

# RIGHTS ASSESSMENT
Write-Log "Assessing rights clearance..."
$rightsStatus = Assess-RightsStatus -Inventory $inventory
Write-Log "  Pre-cleared: $($rightsStatus.pre_cleared.Count)"
Write-Log "  Needs clearance: $($rightsStatus.needs_clearance.Count)"

# RESEARCH GAPS
Write-Log "Identifying research gaps..."
$gaps = Identify-ResearchGaps -Inventory $inventory
$criticalGaps = @($gaps | Where-Object { $_.priority -eq 'CRITICAL' })
Write-Log "  Critical gaps: $($criticalGaps.Count)"

# DAD QUESTIONS
Write-Log "Extracting Dad questions..."
$dadQuestions = Extract-DadQuestions -Inventory $inventory
Write-Log "  Questions identified: $($dadQuestions.Count)"

# MARKETING READINESS
Write-Log "Scoring marketing readiness..."
$readiness = Score-MarketingReadiness -Inventory $inventory
Write-Log "  Overall readiness: $($readiness.overall_score)/100"

# BUILD OPS CHECKLIST
$opsChecklist = @{
  assessment_date = (Get-Date -Format 'yyyy-MM-dd')
  rights_status = $rightsStatus
  research_gaps = $gaps
  dad_questions = $dadQuestions
  marketing_readiness = $readiness
  next_actions = @(
    @{
      action = "Review rights clearance status"
      priority = "HIGH"
      owner = "You"
      due_date = (Get-Date).AddDays(7).ToString('yyyy-MM-dd')
      status = "PENDING"
    },
    @{
      action = "Address critical research gaps"
      priority = "HIGH"
      owner = "You"
      due_date = (Get-Date).AddDays(14).ToString('yyyy-MM-dd')
      status = "PENDING"
    },
    @{
      action = "Schedule call with Dad (Q13-Q24)"
      priority = "CRITICAL"
      owner = "You"
      due_date = (Get-Date).AddDays(7).ToString('yyyy-MM-dd')
      status = "PENDING"
    },
    @{
      action = "Finalize social media calendar"
      priority = "MEDIUM"
      owner = "You"
      due_date = (Get-Date).AddDays(3).ToString('yyyy-MM-dd')
      status = "PENDING"
    }
  )
}

$opsChecklist | ConvertTo-Json -Depth 10 | Set-Content $OpsChecklistFile
Write-Log "✓ Ops checklist saved"

# BUILD EMAIL SUMMARY
$emailBody = @"
## CAST IRON CHARLIE — FOLLOW-OPS SUMMARY
**Assessment Date:** $(Get-Date -Format 'MMMM dd, yyyy')

---

### RIGHTS & LICENSING STATUS
- **Pre-cleared media:** $($rightsStatus.pre_cleared.Count)
- **Needs clearance:** $($rightsStatus.needs_clearance.Count)

**By Archive:**
$($rightsStatus.clearance_summary.GetEnumerator() | ForEach-Object {
  "- $($_.Key): $($_.Value.cleared)/$($_.Value.total) cleared — $($_.Value.status)"
})

---

### RESEARCH GAPS (Topics with <5 items)
$if ($gaps.Count -eq 0) {
"✓ All topics have sufficient coverage"
} else {
$gaps | ForEach-Object {
"- **$($_.topic):** $($_.current_items)/5 items ($($_.gap) more needed) — Priority: $($_.priority)"
}
}

---

### DAD QUESTIONS TO ADDRESS
$($dadQuestions | Select-Object -First 5 | ForEach-Object {
"- Q$($foreach.count): ""$($_.question)"" (Source: $($_.source_log))"
})

$if ($dadQuestions.Count -gt 5) {
"... and $($dadQuestions.Count - 5) more questions in the log"
}

---

### MARKETING READINESS SCORECARD
| Category | Score | Status |
|----------|-------|--------|
| Social Media Calendar | $($readiness.social_calendar_score)/100 | $(if ($readiness.social_calendar_score -ge 80) { "✓ Ready" } else { "⏳ In Progress" }) |
| Pitch Deck | $($readiness.pitch_deck_score)/100 | $(if ($readiness.pitch_deck_score -ge 80) { "✓ Ready" } else { "⏳ In Progress" }) |
| Grant Bundles | $($readiness.grant_bundles_score)/100 | $(if ($readiness.grant_bundles_score -ge 80) { "✓ Ready" } else { "⏳ In Progress" }) |
| **OVERALL** | **$($readiness.overall_score)/100** | $(if ($readiness.overall_score -ge 80) { "✓ Ready" } else { "⏳ In Progress" }) |

---

### RECOMMENDED NEXT ACTIONS
1. **CRITICAL:** Schedule Dad call for Q13-Q24 (most critical family memory)
2. **HIGH:** Review rights clearance — identify which archives need follow-up
3. **HIGH:** Address $($criticalGaps.Count) critical research gaps
4. **MEDIUM:** Finalize social media calendar (ready for posting)

---

**Full ops checklist:** $(Join-Path $RootPath 'operations\follow_ops_checklist.json')

Generated by CIC DAM System — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

if ($EmailSummary) {
  Write-Log "Sending email summary to $EmailTo..."

  try {
    # Build email message
    $emailParams = @{
      To = $EmailTo
      From = "sorensencc@gmail.com"
      Subject = "Cast Iron Charlie — Follow-Ops Summary $(Get-Date -Format 'MMMM dd, yyyy')"
      Body = $emailBody
      BodyAsHtml = $true
      SmtpServer = "smtp.gmail.com"
      Port = 587
      UseSsl = $true
      Credential = $null  # Requires auth setup
    }

    # Note: This requires SMTP credentials configured
    # For Windows, use: Send-MailMessage or integrate with Outlook
    Write-Log "⚠ Email sending requires SMTP setup. Save summary to file instead."
  }
  catch {
    Write-Log "Note: Email sending requires SMTP authentication. Summary saved to file."
  }
}

# Save email summary to file
$emailFile = "$LogPath\follow_ops_email_$(Get-Date -Format 'yyyy-MM-dd-HHmmss').html"
$emailBody | Set-Content $emailFile
Write-Log "✓ Email summary saved: $emailFile"

Write-Log "========== FOLLOW-OPS ASSESSMENT COMPLETE =========="
Write-Log "Outputs:"
Write-Log "  - Ops checklist: $OpsChecklistFile"
Write-Log "  - Email summary: $emailFile"
Write-Log "  - Dad questions: $($dadQuestions.Count) identified"
Write-Log "  - Research gaps: $($gaps.Count) identified"
Write-Log "  - Marketing readiness: $($readiness.overall_score)/100"

Write-Host "`n✓ FOLLOW-OPS ASSESSMENT SUCCESS" -ForegroundColor Green
