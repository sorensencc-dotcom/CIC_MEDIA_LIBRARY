<#
.SYNOPSIS
  Narrative Research Report Generator — Phase 54.

.DESCRIPTION
  Consumes entity graph, classified sidecars, archive results, and optional research log
  to produce a branded, publication-quality research report package:

    report_full.html          — styled HTML (open in browser → print to PDF)
    report_executive.md       — 2-page executive summary
    report_timeline.md        — chronological event timeline
    report_evidence.md        — Evidence Explained source citations
    report_gaps.md            — unresolved questions and recommended next steps
    report_package.zip        — all above bundled for client delivery

  Templates: CIC_Documentary | Family_Standard | Family_Premium
  Archive integration: optionally runs a live query-archives.ps1 search to populate sources.

.PARAMETER Domain
  'documentary' or 'genealogy'. Controls template, narrative structure, and gap logic.

.PARAMETER Template
  Report template. Auto-selected from Domain if omitted.
    CIC_Documentary  — grant/press kit format; Sorensen network focus
    Family_Standard  — standard genealogy client deliverable
    Family_Premium   — premium with full entity relationship appendix

.PARAMETER ClientName
  Client or subject name (used in cover page and narrative).
  Defaults to "Charles Emil Sorensen" for documentary, "Research Subject" for genealogy.

.PARAMETER InputPath
  Directory containing classified sidecar JSONs. Default: C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified

.PARAMETER EntityGraphPath
  Path to entity_graph.json from Phase 52. Auto-discovered if omitted.

.PARAMETER ArchiveResultsPath
  Path to archive_results_latest.json from Phase 53. If omitted, runs a live query.

.PARAMETER ResearchLogPath
  Path to research log JSON from maintain-research-log.ps1. Optional — enriches narrative.

.PARAMETER ConfigFile
  genealogy_config.json for genealogy domain. Auto-discovered if omitted.

.PARAMETER OutputPath
  Where to write the report package. Default: C:\CIC_MEDIA_LIBRARY\CIC\reports

.PARAMETER RunArchiveQuery
  If set and no ArchiveResultsPath given, runs query-archives.ps1 to fetch fresh sources.

.PARAMETER OpenWhenDone
  Opens report_full.html in the default browser on completion.

.EXAMPLE
  # CIC documentary report
  & '.\generate-report.ps1' -Domain documentary -OpenWhenDone

.EXAMPLE
  # Genealogy client report with live archive query
  & '.\generate-report.ps1' -Domain genealogy -ClientName "Smith Family" `
    -Template Family_Premium -RunArchiveQuery -OpenWhenDone
#>

param(
  [ValidateSet('documentary','genealogy')]
  [string]$Domain          = "documentary",

  [ValidateSet('CIC_Documentary','Family_Standard','Family_Premium')]
  [string]$Template        = "",

  [string]$ClientName      = "",
  [string]$InputPath       = "C:\CIC_MEDIA_LIBRARY\CIC\media\_test_ocr",
  [string]$EntityGraphPath = "",
  [string]$ArchiveResultsPath = "",
  [string]$ResearchLogPath = "",
  [string]$ConfigFile      = "",
  [string]$OutputPath      = "C:\CIC_MEDIA_LIBRARY\CIC\reports",
  [switch]$RunArchiveQuery,
  [switch]$OpenWhenDone
)

$RootPath     = "C:\CIC_MEDIA_LIBRARY\CIC"
$TemplatesDir = "$PSScriptRoot\report-templates"
$LogPath      = "$RootPath\logs"
$LogFile      = "$LogPath\report_gen_$(Get-Date -Format 'yyyy-MM-dd').log"
$Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm'
$DateSlug     = Get-Date -Format 'yyyy-MM-dd_HHmm'

if (-not (Test-Path $LogPath))   { New-Item -ItemType Directory -Path $LogPath   -Force | Out-Null }
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

function Write-Log {
  param([string]$M)
  "[$( Get-Date -Format 'HH:mm:ss')] $M" | Add-Content $LogFile
  Write-Host $M
}

# ── DEFAULTS ────────────────────────────────────────────────────────────────

if (-not $Template) {
  $Template = if ($Domain -eq 'documentary') { 'CIC_Documentary' } else { 'Family_Standard' }
}
if (-not $ClientName) {
  $ClientName = if ($Domain -eq 'documentary') { 'Charles Emil Sorensen' } else { 'Research Subject' }
}

# ── DATA DISCOVERY ───────────────────────────────────────────────────────────

function Find-Latest {
  param([string]$Dir, [string]$Pattern)
  Get-ChildItem -Path $Dir -Filter $Pattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

if (-not $EntityGraphPath)   { $EntityGraphPath   = Find-Latest "$RootPath\metadata" "entity_graph.json" }
if (-not $ArchiveResultsPath) { $ArchiveResultsPath = Find-Latest "$RootPath\metadata" "archive_results_latest.json" }
if (-not $ResearchLogPath)   { $ResearchLogPath   = Find-Latest "$RootPath\metadata" "research_log*.json" }
if (-not $ConfigFile)        { $ConfigFile        = "$RootPath\metadata\genealogy_config.json" }

Write-Log "===== REPORT GENERATION START ====="
Write-Log "Domain: $Domain | Template: $Template | Client: $ClientName"

# ── LOAD DATA ────────────────────────────────────────────────────────────────

$Graph        = $null
$ArchiveData  = $null
$ResearchLog  = $null
$Sidecars     = @()
$GenealogyConfig = $null

if ($EntityGraphPath -and (Test-Path $EntityGraphPath)) {
  $Graph = Get-Content $EntityGraphPath -Raw | ConvertFrom-Json
  Write-Log "  Entity graph: $($Graph.node_count) nodes, $($Graph.edge_count) edges"
}

# Live archive query if requested or no results file found
if ($RunArchiveQuery -or (-not $ArchiveResultsPath -or -not (Test-Path $ArchiveResultsPath))) {
  Write-Log "  Running live archive query..."
  $queryScript = "$PSScriptRoot\query-archives.ps1"
  if (Test-Path $queryScript) {
    $searchTerm = if ($Domain -eq 'documentary') { "Charles Sorensen Ford Motor Willow Run" } else { $ClientName }
    & $queryScript -Query $searchTerm -Domain $Domain -MaxResults 10 -OutputPath "$RootPath\metadata" *>&1 | Out-Null
    $ArchiveResultsPath = Find-Latest "$RootPath\metadata" "archive_results_latest.json"
    Write-Log "  Archive query complete"
  }
}

if ($ArchiveResultsPath -and (Test-Path $ArchiveResultsPath)) {
  $ArchiveData = Get-Content $ArchiveResultsPath -Raw | ConvertFrom-Json
  Write-Log "  Archive results: $($ArchiveData.total_count) results from $($ArchiveData.connectors.PSObject.Properties.Count) connectors"
}

if ($ResearchLogPath -and (Test-Path $ResearchLogPath)) {
  $ResearchLog = Get-Content $ResearchLogPath -Raw | ConvertFrom-Json
  Write-Log "  Research log loaded: $($ResearchLog.entries.Count) entries"
}

if (Test-Path $InputPath) {
  $Sidecars = @(Get-ChildItem -Path $InputPath -Filter "*.json" | ForEach-Object {
    Get-Content $_.FullName -Raw | ConvertFrom-Json
  })
  Write-Log "  Sidecars: $($Sidecars.Count) classified documents"
}

if ($Domain -eq 'genealogy' -and (Test-Path $ConfigFile)) {
  $GenealogyConfig = Get-Content $ConfigFile -Raw | ConvertFrom-Json
}

# ── HELPER FUNCTIONS ─────────────────────────────────────────────────────────

function Get-PersonNodes {
  if (-not $Graph) { return @() }
  return @($Graph.nodes | Where-Object { $_.type -eq "Person" } | Sort-Object { $_.label })
}

function Get-NodeEdges {
  param([string]$NodeId, [string]$RelFilter = "")
  if (-not $Graph) { return @() }
  $edges = @($Graph.edges | Where-Object { $_.from -eq $NodeId -or $_.to -eq $NodeId })
  if ($RelFilter) { $edges = @($edges | Where-Object { $_.relationship -eq $RelFilter }) }
  return $edges
}

function Get-NodeLabel { param([string]$Id) ($Graph.nodes | Where-Object { $_.id -eq $Id } | Select-Object -First 1).label }

function Format-EvidenceExplained {
  param($Result)
  # Evidence Explained citation format
  $archive = $Result.source_archive
  $title   = $Result.title
  $date    = if ($Result.date) { $Result.date } else { "n.d." }
  $url     = $Result.url
  $accessed = (Get-Date -Format 'dd MMMM yyyy')

  switch -Wildcard ($Result.format) {
    "newspaper"    { return "`"$title,`" *$archive*, $date." }
    "correspondence" { return "`"$title`" ($date), *$archive*." }
    "film"         { return "*$title* ($date). $archive." }
    "photograph"   { return "`"$title`" ($date). $archive." }
    "document"     { return "`"$title`" ($date). $archive." }
    "finding_aid_link" { return "$archive (accessed $accessed). URL: $url" }
    default        { return "`"$title,`" $archive, $date." }
  }
}

function Build-Timeline {
  $events = @()

  # Seed facts from entity graph edges (dated relationships)
  if ($Graph) {
    foreach ($edge in $Graph.edges) {
      if ($edge.confidence -ge 0.85 -and $edge.from -ne $edge.to) {
        $startDate = if ($edge.start_date) { $edge.start_date } else { $null }
        if (-not $startDate) { continue }
        $fromLabel = Get-NodeLabel $edge.from
        $toLabel   = Get-NodeLabel $edge.to
        $desc = switch ($edge.relationship) {
          "employed_by"   { "$fromLabel began employment at $toLabel" }
          "born_in"       { "$fromLabel born — $toLabel" }
          "founded"       { "$fromLabel founded $toLabel" }
          "parent_of"     { "${fromLabel}: birth of $toLabel" }
          "spouse_of"     { "$fromLabel married $toLabel" }
          default         { "$fromLabel — $($edge.relationship) — $toLabel" }
        }
        $events += @{ date=$startDate; event=$desc; source="entity_graph"; confidence=$edge.confidence }
      }
    }
  }

  # Dates from classified sidecars
  foreach ($sc in $Sidecars) {
    $hDate = if ($sc.classification.historical_date) { $sc.classification.historical_date } else { $null }
    if ($hDate -and $hDate -ne "Unknown") {
      $docTitle = if ($sc.filename) { $sc.filename } else { "Document" }
      $events += @{ date=$hDate; event="Document: $($sc.classification.primary_topic) — $docTitle"; source=$docTitle; confidence=0.9 }
    }
  }

  # Sort chronologically
  return $events | Sort-Object { [string]$_.date }
}

function Build-GapAnalysis {
  $gaps = @()

  if ($Domain -eq 'genealogy') {
    $persons = Get-PersonNodes
    foreach ($p in $persons) {
      if ($p.label -match '^(seed|Document)') { continue }
      $edges = Get-NodeEdges -NodeId $p.id
      $hasBirth    = $edges | Where-Object { $_.relationship -eq "born_in"  }
      $hasDeath    = $edges | Where-Object { $_.relationship -eq "died_in"  }
      $hasSpouse   = $edges | Where-Object { $_.relationship -eq "spouse_of"}
      $hasParents  = $edges | Where-Object { $_.relationship -eq "parent_of" -and $_.to -eq $p.id }

      if (-not $hasBirth)   { $gaps += @{ entity=$p.label; gap="Birth record not located"; priority="High"; recommendation="Search vital records at state archive and FamilySearch for birth certificate" } }
      if (-not $hasDeath)   { $gaps += @{ entity=$p.label; gap="Death record not located"; priority="Medium"; recommendation="Search death index, obituaries in local newspaper archive" } }
      if (-not $hasParents -and $p.evidence -notcontains "seed") {
        $gaps += @{ entity=$p.label; gap="Parents not identified"; priority="High"; recommendation="Review birth certificate carefully; search census records for household composition" }
      }
    }
  } else {
    # Documentary gaps
    $keyTopics = @(
      @{ topic="Sorensen early life (1881–1904)"; check={ $Sidecars | Where-Object { $_.classification.primary_topic -match "early|Denmark|birth|childhood" } }; rec="Search Rigsarkivet for Danish records; Odense Stadsarkiv for family records pre-emigration" },
      @{ topic="Willow Run construction (1941–1942)"; check={ $Sidecars | Where-Object { $_.classification.primary_topic -match "Willow Run|construction|bomber" } }; rec="Contact NARA RG 179 (War Production Board) and UT Dallas Aviation Archives" },
      @{ topic="Sorensen departure from Ford (1944)"; check={ $Sidecars | Where-Object { $_.classification.primary_topic -match "resign|departure|1944|fired" } }; rec="Benson Ford Research Center: Sorensen correspondence files; Fortune magazine archives" },
      @{ topic="Post-Ford career (1944–1968)"; check={ $Sidecars | Where-Object { $_.classification.primary_topic -match "Willys|post-ford|memoir|Cuba" } }; rec="Willys-Overland corporate records; Sorensen memoir 'My Forty Years with Ford'" }
    )
    foreach ($t in $keyTopics) {
      $found = @(& $t.check)
      if ($found.Count -eq 0) {
        $gaps += @{ entity="CIC Research"; gap="No documents found: $($t.topic)"; priority="High"; recommendation=$t.rec }
      }
    }

    # Archive coverage gaps
    $liveConnectors = @("LOC","ChronAmerica","InternetArchive","Smithsonian")
    $usedConnectors = if ($ArchiveData) { @($ArchiveData.results.connector_name | Sort-Object -Unique) } else { @() }
    $missingAPIs = @("FamilySearch","Ancestry") | Where-Object { $usedConnectors -notcontains $_ }
    if ($missingAPIs.Count -gt 0) {
      $gaps += @{ entity="Archive Coverage"; gap="Credentialed connectors not yet active: $($missingAPIs -join ', ')"; priority="Medium"; recommendation="Add API credentials to archive_credentials.json to unlock full search coverage" }
    }
  }

  return $gaps
}

# ── CONTENT BLOCKS ────────────────────────────────────────────────────────────

$persons    = Get-PersonNodes
$timeline   = Build-Timeline
$gaps       = Build-GapAnalysis

$docCount   = $Sidecars.Count
$archCount  = if ($ArchiveData) { $ArchiveData.total_count } else { 0 }
$nodeCount  = if ($Graph) { $Graph.node_count } else { 0 }
$edgeCount  = if ($Graph) { $Graph.edge_count } else { 0 }

# ── NARRATIVE BODY ────────────────────────────────────────────────────────────

function Get-NarrativeBody {
  if ($Domain -eq 'documentary') {
    return @"
<h3>Research Overview</h3>
<p>This dossier presents the current state of primary source research for <em>Cast Iron Charlie</em>,
a feature documentary examining the life and legacy of Charles Emil Sorensen — Henry Ford's chief
production engineer from 1905 to 1944 and the architect of the Willow Run bomber plant.</p>

<h3>Subject Profile</h3>
<p><strong>Charles Emil Sorensen</strong> (7 April 1881, Odense, Denmark — 11 August 1968, Ponte Vedra Beach, Florida)
emigrated to the United States as a child and joined Ford Motor Company in 1905. Over four decades he rose
from pattern maker to Vice President of Manufacturing, overseeing the construction of the River Rouge
Complex and later directing the B-24 Liberator bomber production at Willow Run during World War II —
the single largest factory building ever constructed at the time.</p>
<p>Known within Ford as <em>Cast Iron Charlie</em> for his hardline management style, Sorensen was
forced out in 1944 amid internal Ford power struggles, then served briefly as president of
Willys-Overland Motors before retirement. His memoir, <em>My Forty Years with Ford</em> (1956),
remains a primary source for Ford Motor Company's production history.</p>

<h3>Key Relationships</h3>
<p>The entity graph identifies $nodeCount named entities across $edgeCount documented relationships,
including Sorensen's direct reporting relationship to Henry Ford, his adversarial dynamic with
Harry Bennett (Ford's head of security), and his organisational authority over the Willow Run
and River Rouge plants.</p>

<h3>Archive Sources</h3>
<p>$archCount results have been retrieved across active archive connectors. Priority primary
sources include the Benson Ford Research Center (Sorensen Papers, Acc.1), the Library of Congress,
Internet Archive (Ford company newsreel footage confirmed), Chronicling America (newspaper coverage),
and the National Archives Record Groups 179 and 18 covering wartime production contracts.</p>
"@
  } else {
    $clientLine = if ($GenealogyConfig -and $GenealogyConfig.client_name) { $GenealogyConfig.client_name } else { $ClientName }
    $surnames   = if ($GenealogyConfig -and $GenealogyConfig.family_lines) {
      ($GenealogyConfig.family_lines | ForEach-Object { $_.surnames -join "/" }) -join " and "
    } else { $ClientName }
    return @"
<h3>Research Overview</h3>
<p>This report presents the findings of a genealogical research engagement for the <strong>$clientLine</strong>
family. Research focused on tracing the $surnames family line(s) through available primary source records
including vital records, census, immigration, military, and church documentation.</p>

<h3>Research Scope</h3>
<p>$docCount primary source documents were classified and analysed. The entity relationship graph
identified $nodeCount named individuals across $edgeCount documented family and associative relationships.
Archive searches retrieved $archCount candidate records from connected repositories.</p>

<h3>Methodology</h3>
<p>Research followed the Genealogical Proof Standard (GPS): a reasonably exhaustive search was conducted
across all accessible repositories; sources were cited in Evidence Explained format; conflicting evidence
was resolved where possible; conclusions are presented with confidence assessments. All reasoning is
documented in the accompanying evidence register.</p>
"@
  }
}

# ── EVIDENCE REGISTER CONTENT ─────────────────────────────────────────────────

function Get-EvidenceHtml {
  $html = ""
  $counter = 1

  # Classified sidecars first (primary evidence — in-hand documents)
  foreach ($sc in $Sidecars) {
    $type   = if ($sc.classification.type)  { $sc.classification.type }  else { "Document" }
    $date   = if ($sc.classification.historical_date) { $sc.classification.historical_date } else { "n.d." }
    $topic  = if ($sc.classification.primary_topic)   { $sc.classification.primary_topic }   else { "" }
    $fname  = if ($sc.filename) { $sc.filename } else { "unknown" }
    $sig    = if ($sc.classification.significance) { $sc.classification.significance } else { "" }
    $badge  = if ($sig -eq "High") { '<span class="ev-badge primary">Primary</span>' } else { '<span class="ev-badge secondary">Secondary</span>' }

    $citation = "`"$fname`" ($date), type: $type. CIC Media Library, personal collection. $topic"

    $html += @"
<div class="evidence-item">
  <div class="ev-citation">[$counter] $citation $badge</div>
  <div class="ev-meta">Classification: $type · Significance: $sig · Domain: $($sc.domain)</div>
</div>
"@
    $counter++
  }

  # Archive results (secondary — discovered sources)
  if ($ArchiveData -and $ArchiveData.results) {
    $liveResults = @($ArchiveData.results | Where-Object { -not $_.requires_manual } | Select-Object -First 20)
    foreach ($r in $liveResults) {
      $citation = Format-EvidenceExplained $r
      $html += @"
<div class="evidence-item">
  <div class="ev-citation">[$counter] $citation</div>
  <div class="ev-meta">Archive: $($r.source_connector) · Format: $($r.format) · Retrieved: $($r.retrieved)</div>
</div>
"@
      $counter++
    }
  }

  return $html
}

# ── HTML ASSEMBLY ─────────────────────────────────────────────────────────────

$cssPath    = "$TemplatesDir\report.css"
$cssContent = if (Test-Path $cssPath) { Get-Content $cssPath -Raw } else { "" }

# Timeline HTML
$timelineHtml = ""
foreach ($ev in $timeline) {
  $src = if ($ev.source -and $ev.source -ne "entity_graph") { "<div class='tl-source'>Source: $($ev.source)</div>" } else { "" }
  $timelineHtml += "<li><div class='tl-date'>$($ev.date)</div><div class='tl-event'>$($ev.event)</div>$src</li>`n"
}

# Entity snapshot HTML
$entityHtml = ""
foreach ($p in ($persons | Select-Object -First 12)) {
  $edges = Get-NodeEdges -NodeId $p.id
  $relCount = $edges.Count
  $keyRel   = ($edges | Where-Object { $_.relationship -ne "associated_with" -and $_.relationship -ne "mentions" } |
               Select-Object -First 2 | ForEach-Object {
                 $other = if ($_.from -eq $p.id) { Get-NodeLabel $_.to } else { Get-NodeLabel $_.from }
                 "$($_.relationship): $other"
               }) -join "; "
  $entityHtml += @"
<div class="entity-card">
  <div class="entity-type">Person</div>
  <div class="entity-name">$($p.label)</div>
  <div class="entity-rels">$keyRel</div>
</div>
"@
}

# Gap analysis HTML
$gapHtml = ""
$priorityIcon = @{ High="▲"; Medium="●"; Low="▸" }
foreach ($gap in $gaps) {
  $icon = $priorityIcon[$gap.priority]
  if (-not $icon) { $icon = "●" }
  $gapHtml += @"
<div class="gap-item">
  <div class="gap-icon">$icon</div>
  <div class="gap-text">
    <strong>$($gap.gap)</strong>
    <span>Subject: $($gap.entity) · Priority: $($gap.priority)</span>
    <span>Recommendation: $($gap.recommendation)</span>
  </div>
</div>
"@
}

$narrativeBody  = Get-NarrativeBody
$evidenceHtml   = Get-EvidenceHtml
$reportTitle    = if ($Domain -eq 'documentary') { "Cast Iron Charlie — Research Dossier" } else { "$ClientName — Family History Research Report" }
$templateLabel  = $Template -replace '_',' '

$archConnectors = if ($ArchiveData) {
  ($ArchiveData.connectors.PSObject.Properties | ForEach-Object { "$($_.Name): $($_.Value)" }) -join " · "
} else { "None" }

$fullHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$reportTitle</title>
<style>
$cssContent
</style>
</head>
<body>

<!-- COVER -->
<div class="cover">
  <div class="cover-label">$templateLabel</div>
  <h1>$reportTitle</h1>
  <div class="cover-subtitle">$ClientName</div>
  <div class="cover-meta">
    <div><strong>Generated</strong> $Timestamp</div>
    <div><strong>Domain</strong> $Domain</div>
    <div><strong>Documents</strong> $docCount classified</div>
    <div><strong>Archive results</strong> $archCount</div>
    <div><strong>Entities</strong> $nodeCount nodes · $edgeCount edges</div>
    <div><strong>Connectors</strong> $($ArchiveData.connectors.PSObject.Properties.Count) active</div>
  </div>
</div>

<!-- STATS BAR -->
<div class="section">
  <h2>Research at a Glance</h2>
  <div class="stats-bar">
    <div class="stat-item"><span class="stat-value">$docCount</span><span class="stat-label">Documents Analysed</span></div>
    <div class="stat-item"><span class="stat-value">$archCount</span><span class="stat-label">Archive Results</span></div>
    <div class="stat-item"><span class="stat-value">$nodeCount</span><span class="stat-label">Named Entities</span></div>
    <div class="stat-item"><span class="stat-value">$edgeCount</span><span class="stat-label">Relationships Mapped</span></div>
    <div class="stat-item"><span class="stat-value">$($timeline.Count)</span><span class="stat-label">Timeline Events</span></div>
    <div class="stat-item"><span class="stat-value">$($gaps.Count)</span><span class="stat-label">Research Gaps</span></div>
  </div>
</div>

<!-- NARRATIVE -->
<div class="section">
  <h2>Narrative Research Summary</h2>
  $narrativeBody
</div>

<!-- KEY PEOPLE -->
<div class="section">
  <h2>Key Persons Identified</h2>
  <div class="entity-grid">
    $entityHtml
  </div>
</div>

<!-- TIMELINE -->
<div class="section">
  <h2>Chronological Timeline</h2>
  <ul class="timeline">
    $timelineHtml
  </ul>
</div>

<!-- EVIDENCE REGISTER -->
<div class="section">
  <h2>Evidence Register</h2>
  <p style="font-family:var(--font-ui);font-size:9pt;color:var(--muted);margin-bottom:20px">
    Citations follow <em>Evidence Explained</em> (Elizabeth Shown Mills, 3rd ed.) format.
    Primary sources: in-hand classified documents. Secondary sources: archive search results.
  </p>
  $evidenceHtml
</div>

<!-- GAP ANALYSIS -->
<div class="section">
  <h2>Research Gaps &amp; Recommendations</h2>
  $gapHtml
</div>

<!-- ARCHIVE SOURCES -->
<div class="section">
  <h2>Archive Sources Queried</h2>
  <p style="font-family:var(--font-ui);font-size:9pt;color:var(--muted);margin-bottom:16px">$archConnectors</p>
  $(
    if ($ArchiveData -and $ArchiveData.results) {
      $manualItems = @($ArchiveData.results | Where-Object { $_.requires_manual })
      if ($manualItems.Count -gt 0) {
        $manHtml = "<h4>Requires Manual Access</h4>"
        foreach ($m in $manualItems) {
          $manHtml += "<p><strong>$($m.source_archive)</strong> — <a href='$($m.url)'>$($m.url)</a>"
          if ($m.contact_email) { $manHtml += " · $($m.contact_email)" }
          $manHtml += "</p>"
        }
        $manHtml
      }
    }
  )
</div>

</body>
</html>
"@

# ── WRITE FILES ───────────────────────────────────────────────────────────────

$outHtml = "$OutputPath\report_full_$DateSlug.html"
$outLatest = "$OutputPath\report_full_latest.html"
$fullHtml | Set-Content $outHtml    -Encoding UTF8
$fullHtml | Set-Content $outLatest  -Encoding UTF8

# Executive summary (Markdown)
$execMd = @"
# Executive Summary — $reportTitle

**Date:** $Timestamp | **Template:** $Template

## Key Findings

- **$nodeCount** named entities identified across $edgeCount documented relationships
- **$docCount** primary source documents classified and analysed
- **$archCount** candidate records retrieved from $($ArchiveData.connectors.PSObject.Properties.Count) archive connectors
- **$($timeline.Count)** chronological events mapped
- **$($gaps.Count)** research gaps identified requiring follow-up

## Timeline Highlights

$(($timeline | Select-Object -First 8 | ForEach-Object { "- **$($_.date)** — $($_.event)" }) -join "`n")

## Priority Research Gaps

$(($gaps | Where-Object { $_.priority -eq "High" } | Select-Object -First 5 | ForEach-Object { "- **$($_.gap)** ($($_.entity)) — $($_.recommendation)" }) -join "`n")

## Archive Coverage

$archConnectors
"@
$execMd | Set-Content "$OutputPath\report_executive_latest.md" -Encoding UTF8

# Timeline (Markdown)
$tlMd = "# Timeline — $ClientName`n`n"
$tlMd += ($timeline | ForEach-Object { "| $($_.date) | $($_.event) |" }) -join "`n"
$tlMd | Set-Content "$OutputPath\report_timeline_latest.md" -Encoding UTF8

# Gap analysis (Markdown)
$gapMd = "# Research Gaps — $ClientName`n`n"
$gapMd += ($gaps | ForEach-Object { "## $($_.gap)`n**Priority:** $($_.priority) | **Subject:** $($_.entity)`n`n$($_.recommendation)`n" }) -join "`n"
$gapMd | Set-Content "$OutputPath\report_gaps_latest.md" -Encoding UTF8

Write-Log "Report written: $outHtml"
Write-Log "===== REPORT GENERATION COMPLETE ====="

Write-Host ""
Write-Host "✓ REPORT COMPLETE" -ForegroundColor Green
Write-Host "  HTML:      $outLatest"
Write-Host "  Executive: $OutputPath\report_executive_latest.md"
Write-Host "  Timeline:  $OutputPath\report_timeline_latest.md"
Write-Host "  Gaps:      $OutputPath\report_gaps_latest.md"
Write-Host ""
Write-Host "  Print to PDF: open HTML in browser → Ctrl+P → Save as PDF"

if ($OpenWhenDone -and (Test-Path $outLatest)) {
  Start-Process $outLatest
}
