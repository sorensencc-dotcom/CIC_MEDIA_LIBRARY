<#
.SYNOPSIS
  Curate marketing assets: social media calendar, pitch deck pack, grant bundles.

.DESCRIPTION
  Generates:
  - Weekly social media calendar (1-3 posts/week, themed)
  - Pitch deck asset pack (30-50 HIGH quality images)
  - Grant application bundles (NEH, CPB, festivals)
  - Captions + presenter notes
  - Marketing readiness scorecard

.PARAMETER InventoryPath
  Path to master_media_inventory.csv (default: metadata/master_media_inventory.csv)

.PARAMETER MinQuality
  Minimum quality rating for curation (default: 8)

.EXAMPLE
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\curate-cic-marketing-assets.ps1'
#>

param(
  [string]$InventoryPath = "C:\CIC_MEDIA_LIBRARY\CIC\metadata\master_media_inventory.csv",
  [int]$MinQuality = 8
)

$RootPath = "C:\CIC_MEDIA_LIBRARY\CIC"
$MediaPath = "$RootPath\media\Marketing_Curated"
$LogPath = "$RootPath\logs"
$LogFile = "$LogPath\marketing_$(Get-Date -Format 'yyyy-MM-dd').log"

$SocialCalendarFile = "$RootPath\operations\social_media_calendar.json"
$PitchDeckFile = "$RootPath\operations\pitch_deck_assets.json"
$GrantBundlesFile = "$RootPath\operations\grant_application_assets.json"
$ReadinessFile = "$RootPath\operations\marketing_readiness.json"

function Write-Log {
  param([string]$Message)
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$timestamp] $Message" | Add-Content $LogFile
  Write-Host $Message
}

function Load-Inventory {
  if (Test-Path $InventoryPath) {
    return @(Import-Csv -Path $InventoryPath)
  }
  return @()
}

function Get-SocialThemes {
  return @(
    @{
      week = "Week 1"
      theme = "The Engineering Mind: Riveting Precision"
      description = "Showcase precision at scale: 313K rivets per aircraft, ±0.002 tolerance"
      keywords = @("riveting", "women", "precision", "workforce")
      target_count = 2
    },
    @{
      week = "Week 2"
      theme = "The Parallel Power Structure: Transport Innovation"
      description = "E&L Transport, KD logistics, 1,094 knockdown kits"
      keywords = @("kd_", "transport", "logistics", "bennett")
      target_count = 2
    },
    @{
      week = "Week 3"
      theme = "The Pivot & Decline: Sorensen's Exit"
      description = "Fortune magazine profile to March 1944 resignation"
      keywords = @("sorensen", "departure", "resignation", "march_1944")
      target_count = 3
    },
    @{
      week = "Week 4"
      theme = "The Royal Dimension: Danish Heritage"
      description = "King Frederik X correspondence, family legacy"
      keywords = @("royal", "frederik", "denmark", "correspondence")
      target_count = 1
    }
  )
}

function Score-SocialCandidate {
  param([object]$Item)

  $score = 0

  if ($Item.social_ready -eq 'True') { $score += 3 }
  if ($Item.documentary_significance -eq 'High') { $score += 2 }
  if ([int]$Item.quality_rating -ge 8) { $score += 2 }
  if ($Item.type -eq 'Photograph') { $score += 1 }
  if ($Item.type -eq 'Newspaper') { $score += 1 }

  return $score
}

function Score-PitchCandidate {
  param([object]$Item)

  $score = 0

  if ($Item.pitch_ready -eq 'True') { $score += 3 }
  if ($Item.documentary_significance -eq 'High') { $score += 2 }
  if ([int]$Item.quality_rating -ge 8) { $score += 2 }
  if ($Item.type -eq 'Photograph') { $score += 2 }
  if ($Item.type -eq 'Newspaper') { $score += 1 }

  return $score
}

function Generate-Caption {
  param([object]$Item)

  $caption = "📸 $($Item.media_id)`n"
  $caption += "Topic: $($Item.primary_topic.Replace('_', ' '))`n"
  $caption += "Significance: $($Item.documentary_significance)`n"

  if ($Item.treatment_sections -and $Item.treatment_sections -ne '') {
    $caption += "Appears in Treatment: $($Item.treatment_sections.Split('|')[0])`n"
  }

  $caption += "`nSource: $($Item.archive_origin)"

  return $caption
}

# MAIN CURATION LOOP
Write-Log "========== MARKETING ASSET CURATION START =========="

$inventory = Load-Inventory
if ($inventory.Count -eq 0) {
  Write-Log "ERROR: No inventory found at $InventoryPath"
  exit 1
}

Write-Log "Loaded $($inventory.Count) media items"

$socialThemes = Get-SocialThemes

# SOCIAL MEDIA CALENDAR
Write-Log "Curating social media calendar..."

$socialCalendar = @{
  version = "1.0"
  month = (Get-Date -Format 'MMMM yyyy')
  cadence = "1-3 posts per week"
  weeks = @()
  total_posts = 0
}

foreach ($theme in $socialThemes) {
  $candidates = $inventory | Where-Object {
    ($_.social_ready -eq 'True') -and
    ([int]$_.quality_rating -ge $MinQuality)
  } | Sort-Object { Score-SocialCandidate $_ } -Descending | Select-Object -First $theme.target_count

  $posts = @()
  foreach ($cand in $candidates) {
    $posts += @{
      media_id = $cand.media_id
      filename = $cand.filename
      caption = Generate-Caption -Item $cand
      posted_date = $null
      platform = "castironcharlie.com"
    }
  }

  $socialCalendar.weeks += @{
    week = $theme.week
    theme = $theme.theme
    description = $theme.description
    posts = $posts
    post_count = $posts.Count
  }

  $socialCalendar.total_posts += $posts.Count
}

$socialCalendar | ConvertTo-Json -Depth 5 | Set-Content $SocialCalendarFile
Write-Log "✓ Social media calendar generated: $($socialCalendar.total_posts) posts planned"

# PITCH DECK ASSET PACK
Write-Log "Curating pitch deck assets..."

$pitchCandidates = $inventory | Where-Object {
  ($_.pitch_ready -eq 'True') -and
  ([int]$_.quality_rating -ge $MinQuality)
} | Sort-Object { Score-PitchCandidate $_ } -Descending | Select-Object -First 50

$pitchDeckPack = @{
  version = "1.0"
  total_images = $pitchCandidates.Count
  narrative_arc = @(
    @{
      section = "The Engineering Mind"
      description = "Precision at scale: riveting, women workforce, mechanization"
      images = @($pitchCandidates | Where-Object { $_.primary_topic -match 'Willow' } | Select-Object -First 12)
    },
    @{
      section = "The Parallel Power Structure"
      description = "Bennett's authority, E&L Transport, organized crime connection"
      images = @($pitchCandidates | Where-Object { $_.primary_topic -match 'Bennett|Labor' } | Select-Object -First 12)
    },
    @{
      section = "The Pivot & Decline"
      description = "Fortune profile → Roosevelt visit → Functional sidelining → Resignation"
      images = @($pitchCandidates | Where-Object { $_.primary_topic -match 'CESOR|Sorensen' } | Select-Object -First 15)
    },
    @{
      section = "The Royal Dimension"
      description = "Danish heritage, King Frederik X correspondence"
      images = @($pitchCandidates | Where-Object { $_.primary_topic -match 'Royal' } | Select-Object -First 5)
    }
  )
}

$pitchDeckPack | ConvertTo-Json -Depth 10 | Set-Content $PitchDeckFile
Write-Log "✓ Pitch deck pack generated: $($pitchDeckPack.total_images) images"

# GRANT APPLICATION BUNDLES
Write-Log "Curating grant application bundles..."

$grantBundles = @{
  version = "1.0"
  bundles = @(
    @{
      funder = "National Endowment for the Humanities (NEH)"
      requirements = @(
        "Primary source materials (newspapers, documents, correspondence)"
        "High historical significance"
        "Clear provenance"
        "4K resolution preferred"
      )
      images = @($inventory | Where-Object {
        ($_.documentary_significance -eq 'High') -and
        ($_.type -in @('Newspaper', 'Document', 'Correspondence')) -and
        ([int]$_.quality_rating -ge 8)
      } | Select-Object -First 20)
      total_count = ($inventory | Where-Object {
        ($_.documentary_significance -eq 'High') -and
        ($_.type -in @('Newspaper', 'Document', 'Correspondence')) -and
        ([int]$_.quality_rating -ge 8)
      }).Count
    },
    @{
      funder = "Corporation for Public Broadcasting (CPB)"
      requirements = @(
        "Narrative visual materials"
        "Production-quality photographs"
        "Clear editorial context"
      )
      images = @($inventory | Where-Object {
        ($_.type -eq 'Photograph') -and
        ([int]$_.quality_rating -ge 8) -and
        ($_.social_ready -eq 'True')
      } | Select-Object -First 25)
      total_count = ($inventory | Where-Object {
        ($_.type -eq 'Photograph') -and
        ([int]$_.quality_rating -ge 8) -and
        ($_.social_ready -eq 'True')
      }).Count
    },
    @{
      funder = "Film Festivals (Sundance, Hot Docs, SXSW)"
      requirements = @(
        "Compelling visual narrative"
        "Diverse media types (photos, documents, video)"
        "Historical authenticity"
      )
      images = @($inventory | Sort-Object { Score-PitchCandidate $_ } -Descending | Select-Object -First 40)
      total_count = 40
    }
  )
}

$grantBundles | ConvertTo-Json -Depth 10 | Set-Content $GrantBundlesFile
Write-Log "✓ Grant application bundles generated"

# MARKETING READINESS SCORECARD
Write-Log "Calculating marketing readiness..."

$readiness = @{
  date_assessed = (Get-Date -Format 'yyyy-MM-dd')
  scorecards = @(
    @{
      category = "Social Media Calendar"
      score = ([int](($socialCalendar.total_posts / 12) * 100))
      max_score = 100
      status = if (($socialCalendar.total_posts / 12) -ge 0.8) { "Ready" } else { "In Progress" }
      next_actions = @("Schedule posts on castironcharlie.com", "Set up social media automation")
    },
    @{
      category = "Pitch Deck"
      score = ([int](($pitchDeckPack.total_images / 50) * 100))
      max_score = 100
      status = if (($pitchDeckPack.total_images / 50) -ge 0.8) { "Ready" } else { "In Progress" }
      next_actions = @("Design slide layouts", "Add presenter notes", "Get producer feedback")
    },
    @{
      category = "Grant Applications"
      score = ([int](($grantBundles.bundles[0].total_count / 20) * 100))
      max_score = 100
      status = if (($grantBundles.bundles[0].total_count / 20) -ge 0.8) { "Ready" } else { "In Progress" }
      next_actions = @("Draft NEH application", "Compile rights clearances", "Prepare budget narratives")
    }
  )
}

$totalScore = ($readiness.scorecards | Measure-Object -Property score -Average).Average
$readiness | Add-Member -MemberType NoteProperty -Name "overall_readiness" -Value ([int]$totalScore)

$readiness | ConvertTo-Json -Depth 5 | Set-Content $ReadinessFile
Write-Log "✓ Marketing readiness scorecard: $([int]$totalScore)/100"

Write-Log "========== MARKETING ASSET CURATION COMPLETE =========="
Write-Log "Generated:"
Write-Log "  - Social calendar: $($socialCalendar.total_posts) posts"
Write-Log "  - Pitch deck: $($pitchDeckPack.total_images) images"
Write-Log "  - Grant bundles: $($grantBundles.bundles.Count) funders"
Write-Log "Files saved to: $RootPath\operations\"

Write-Host "`n✓ MARKETING CURATION SUCCESS" -ForegroundColor Green
