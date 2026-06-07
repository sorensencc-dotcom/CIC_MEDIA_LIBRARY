<#
.SYNOPSIS
  Build a Person/Entity Relationship Graph from classified media sidecars. Phase 52.

.DESCRIPTION
  Reads all sidecar JSONs in a directory and constructs a graph of:
    Nodes: Person, Place, Organization, Event, Document
    Edges: family, organizational, geographic, temporal, associative relationships

  Edge sources (in priority order):
    1. Vital record parsing  — birth/death/marriage certs yield explicit family relationships
    2. Domain seed facts     — pre-populated known relationships (Sorensen network for documentary)
    3. Co-occurrence         — entities sharing a document get an "associated_with" edge

  Outputs:
    metadata/entity_graph.json      — full node-link graph (D3/Cytoscape compatible)
    metadata/entity_graph_summary.md — human-readable relationship summary
    metadata/entity_graph.ged        — GEDCOM 5.5.1 export (genealogy mode only)

.PARAMETER InputPath
  Directory of sidecar JSONs. Default: C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified

.PARAMETER Domain
  'documentary' or 'genealogy'. Controls seed relationships, alias tables, and GEDCOM export.

.PARAMETER ConfigFile
  Path to genealogy_config.json (genealogy mode). Auto-discovered if omitted.

.PARAMETER OutputPath
  Where to write graph files. Default: C:\CIC_MEDIA_LIBRARY\CIC\metadata

.EXAMPLE
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\build-entity-graph.ps1' `
    -InputPath 'C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified' `
    -Domain documentary

.EXAMPLE
  & 'C:\CIC_MEDIA_LIBRARY\CIC\scripts\build-entity-graph.ps1' `
    -InputPath 'C:\FamilyResearch\Smith_Family\classified' `
    -Domain genealogy `
    -ConfigFile 'C:\FamilyResearch\Smith_Family\genealogy_config.json'
#>

param(
  [string]$InputPath  = "C:\CIC_MEDIA_LIBRARY\CIC\media\_Inbox\classified",
  [ValidateSet('documentary','genealogy')]
  [string]$Domain     = "documentary",
  [string]$ConfigFile = "",
  [string]$OutputPath = "C:\CIC_MEDIA_LIBRARY\CIC\metadata"
)

$RootPath = "C:\CIC_MEDIA_LIBRARY\CIC"
$LogPath  = "$RootPath\logs"
$LogFile  = "$LogPath\entity_graph_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log {
  param([string]$Message)
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$ts] $Message" | Add-Content $LogFile
  Write-Host $Message
}

# ---------------------------------------------------------------------------
# ALIAS RESOLUTION  — canonical name tables
# ---------------------------------------------------------------------------

# Documentary: map all known variants to canonical form
$AliasTable_Documentary = @{
  'Sorensen'              = 'Charles Emil Sorensen'
  'Charles Sorensen'      = 'Charles Emil Sorensen'
  'C.E. Sorensen'         = 'Charles Emil Sorensen'
  'Cast Iron Charlie'     = 'Charles Emil Sorensen'
  'Bennett'               = 'Harry Bennett'
  'Ford'                  = 'Henry Ford'
  'Ford Motor'            = 'Ford Motor Company'
  'Ford Motor Co'         = 'Ford Motor Company'
  'UAW'                   = 'United Auto Workers'
  'Rouge Plant'           = 'River Rouge Plant'
  'Willow Run Plant'      = 'Willow Run Bomber Plant'
  'Willow Run'            = 'Willow Run Bomber Plant'
  'Willys'                = 'Willys-Overland Motors'
  'Willys Overland'       = 'Willys-Overland Motors'
  'Willys-Overland'       = 'Willys-Overland Motors'
  'Overland Motors'       = 'Willys-Overland Motors'
}

# Noise strings to always reject as entity names
$RejectPatterns = @(
  '^\d',               # starts with digit
  '^(The|And|For|With|From|This|That|They|Their|There|When|Where|Which|Have|Will|Was|Were|Has|Had|Are|But|Not|All)\b',
  'Output Targets',
  'War Production Boar',  # OCR truncation artifact
  'Production Boar',
  '^Mr\.?$',
  '^Mrs\.?$',
  '^Dr\.?$',
  'Full Name',
  'Registration No',
  'Attending Physician',
  'County Registrar',
  'Date of Birth',
  'Place of Birth',
  'Live Birth',
  '^Age$',
  '^Born$',
  '^Father$','^Mother$','^Child$','^Husband$','^Wife$','^Bride$','^Groom$',
  '^\s*$',
  '\s+Age$',           # "Denmark Age" — form field value smeared onto adjacent word
  '\s+Father$',        # "Michigan Father" — same artifact
  '\s+Mother$',
  'Certified$',        # "Mason Certified" — form stamp noise
  '^Mason\b',          # lodge/fraternal artifacts common in old certs
  '\bNo\.\s*\d',       # "Registration No. 12345"
  '^\w+\s+(County|Township|Village|Parish|District)$'  # pure geographic labels
)

# Keywords for type-override when OCR lumps orgs/places into the people list
$OrgKeywords   = 'Company|Corporation|Corp|Motors|Department|Dept|Bureau|Agency|' +
                 'Institute|University|College|Services|Industries|Association|Committee|' +
                 'Board|Authority|Administration|Commission|Division|Group|Inc\.|Ltd\.|Co\.'
$PlaceKeywords = 'Plant|Factory|Works|Rouge|Rouge Plant|Willow Run|River |Lake |Mountain|' +
                 'County|City|Township|Village|Street|Avenue|Boulevard|Road|Drive|Park'

function Infer-EntityType {
  param([string]$Label, [string]$DefaultType)
  if ($Label -match "($OrgKeywords)")  { return "Organization" }
  if ($DefaultType -ne "Organization") {
    if ($Label -match "($PlaceKeywords)") { return "Place" }
  }
  return $DefaultType
}

function Resolve-Name {
  param([string]$Raw, [hashtable]$Aliases)

  $clean = $Raw -replace "`n"," " -replace "\s+"," " -replace "^\s+|\s+$",""

  # Reject noise
  foreach ($pat in $RejectPatterns) {
    if ($clean -match $pat) { return $null }
  }
  if ($clean.Length -lt 3) { return $null }

  # Apply alias table
  if ($Aliases.ContainsKey($clean)) { return $Aliases[$clean] }

  return $clean
}

function Make-NodeId {
  param([string]$Label, [string]$Type)
  $slug = $Label.ToLower() -replace '[^a-z0-9]','_' -replace '_+','_' -replace '^_|_$',''
  return "${Type}_${slug}"
}

# ---------------------------------------------------------------------------
# DOCUMENTARY SEED FACTS
# Establishes the known Sorensen network before any document evidence.
# ---------------------------------------------------------------------------

function Get-DocumentarySeedFacts {
  return @(
    # Employment relationships
    @{ from="Charles Emil Sorensen"; from_type="Person"; to="Ford Motor Company"; to_type="Organization";
       rel="employed_by"; rel_type="organizational"; start="1905"; end="1944"; confidence=1.0;
       note="Production Engineer; rose to VP of Manufacturing" },

    @{ from="Harry Bennett"; from_type="Person"; to="Ford Motor Company"; to_type="Organization";
       rel="employed_by"; rel_type="organizational"; start="1916"; end="1945"; confidence=1.0;
       note="Head of Ford Service Department" },

    @{ from="Henry Ford"; from_type="Person"; to="Ford Motor Company"; to_type="Organization";
       rel="founded"; rel_type="organizational"; start="1903"; confidence=1.0; end=""; note="" },

    @{ from="Charles Emil Sorensen"; from_type="Person"; to="Henry Ford"; to_type="Person";
       rel="reported_to"; rel_type="organizational"; start="1905"; end="1944"; confidence=1.0;
       note="Direct report; primary production relationship" },

    @{ from="Harry Bennett"; from_type="Person"; to="Henry Ford"; to_type="Person";
       rel="reported_to"; rel_type="organizational"; start="1916"; end="1945"; confidence=0.9;
       note="Head of Ford Service Dept; close personal confidant" },

    @{ from="Charles Emil Sorensen"; from_type="Person"; to="Harry Bennett"; to_type="Person";
       rel="adversarial_with"; rel_type="organizational"; start="1930"; end="1944"; confidence=0.85;
       note="Competing power centers within Ford Motor Company" },

    # Geographic / birthplace
    @{ from="Charles Emil Sorensen"; from_type="Person"; to="Odense, Denmark"; to_type="Place";
       rel="born_in"; rel_type="geographic"; start="1881"; confidence=1.0; end=""; note="" },

    @{ from="Charles Emil Sorensen"; from_type="Person"; to="Detroit"; to_type="Place";
       rel="lived_in"; rel_type="geographic"; start="1905"; end="1944"; confidence=0.9; note="" },

    @{ from="Henry Ford"; from_type="Person"; to="Dearborn"; to_type="Place";
       rel="lived_in"; rel_type="geographic"; start="1900"; end="1947"; confidence=1.0; note="" },

    # Organizational geography
    @{ from="Ford Motor Company"; from_type="Organization"; to="River Rouge Plant"; to_type="Place";
       rel="operates"; rel_type="geographic"; start="1927"; confidence=1.0; end=""; note="" },

    @{ from="Ford Motor Company"; from_type="Organization"; to="Willow Run Bomber Plant"; to_type="Place";
       rel="operates"; rel_type="geographic"; start="1942"; end="1945"; confidence=1.0; note="Built for B-24 Liberator production" },

    @{ from="Willow Run Bomber Plant"; from_type="Place"; to="Ypsilanti"; to_type="Place";
       rel="located_in"; rel_type="geographic"; start="1942"; confidence=1.0; end=""; note="" },

    # Post-Ford
    @{ from="Charles Emil Sorensen"; from_type="Person"; to="Willys-Overland Motors"; to_type="Organization";
       rel="employed_by"; rel_type="organizational"; start="1944"; end="1946"; confidence=0.9;
       note="President after leaving Ford" },

    # Royal connection
    @{ from="Charles Emil Sorensen"; from_type="Person"; to="King Frederik X"; to_type="Person";
       rel="corresponded_with"; rel_type="associative"; start="1950"; end="1968"; confidence=0.85;
       note="Danish heritage correspondence" }
  )
}

# ---------------------------------------------------------------------------
# VITAL RECORD PARSER — extracts family relationships from OCR text
# ---------------------------------------------------------------------------

function Parse-VitalRecordRelationships {
  param([string]$OcrText, [string]$DocType, [string]$DocId)

  $relationships = @()
  if (-not $OcrText) { return $relationships }

  $lines = $OcrText -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

  # Collect structured fields
  $fields = @{}
  foreach ($line in $lines) {
    if ($line -match '^\s*(Full\s+Name(?:\s+of\s+Child)?|Child|Name)\s*[:\-]\s*(.+)$') {
      $fields['child'] = $matches[2].Trim()
    } elseif ($line -match '^\s*Father\s*[:\-]\s*(.+)$') {
      $fields['father'] = $matches[1].Trim()
    } elseif ($line -match '^\s*Mother\s*[:\-]\s*(.+)$') {
      $fields['mother'] = $matches[1].Trim()
    } elseif ($line -match '^\s*Husband\s*[:\-]\s*(.+)$') {
      $fields['husband'] = $matches[1].Trim()
    } elseif ($line -match '^\s*Wife|Bride\s*[:\-]\s*(.+)$') {
      $fields['wife'] = $matches[1].Trim()
    } elseif ($line -match '^\s*Groom\s*[:\-]\s*(.+)$') {
      $fields['groom'] = $matches[1].Trim()
    } elseif ($line -match '^\s*Deceased\s*[:\-]\s*(.+)$') {
      $fields['deceased'] = $matches[1].Trim()
    } elseif ($line -match '(Born|Birth|BIRT)\s*[:\-]?\s*(.{3,})$') {
      $fields['born_detail'] = $matches[2].Trim()
    } elseif ($line -match '(Died|Death|DEAT)\s*[:\-]?\s*(.{3,})$') {
      $fields['died_detail'] = $matches[2].Trim()
    }
  }

  # Birth certificate → parent-child edges + spouse edge
  if ($DocType -eq 'Birth_Certificate' -and $fields['child']) {
    $child = $fields['child']

    if ($fields['father']) {
      $relationships += @{
        from="$($fields['father'])"; from_type="Person"
        to=$child; to_type="Person"
        rel="parent_of"; rel_type="family"
        parent_role="father"; evidence=$DocId; confidence=0.95
      }
    }
    if ($fields['mother']) {
      $relationships += @{
        from="$($fields['mother'])"; from_type="Person"
        to=$child; to_type="Person"
        rel="parent_of"; rel_type="family"
        parent_role="mother"; evidence=$DocId; confidence=0.95
      }
    }
    if ($fields['father'] -and $fields['mother']) {
      $relationships += @{
        from="$($fields['father'])"; from_type="Person"
        to="$($fields['mother'])"; to_type="Person"
        rel="spouse_of"; rel_type="family"
        evidence=$DocId; confidence=0.8
        note="Inferred from shared parentage on birth certificate"
      }
    }
  }

  # Marriage record → spouse edge
  if ($DocType -eq 'Marriage_Record') {
    $p1 = if ($fields['husband']) { $fields['husband'] } elseif ($fields['groom']) { $fields['groom'] } else { $null }
    $p2 = if ($fields['wife'])    { $fields['wife']    } elseif ($fields['bride']) { $fields['bride'] } else { $null }
    if ($p1 -and $p2) {
      $relationships += @{
        from=$p1; from_type="Person"; to=$p2; to_type="Person"
        rel="spouse_of"; rel_type="family"
        evidence=$DocId; confidence=0.98
      }
    }
  }

  # Death certificate → person-place (died-in) edge
  if ($DocType -eq 'Death_Certificate' -and $fields['deceased']) {
    # Place is often on a "Place of Death:" line — captured separately if needed
  }

  return $relationships
}

# ---------------------------------------------------------------------------
# GRAPH BUILDER
# ---------------------------------------------------------------------------

$Nodes   = @{}  # id → node object
$Edges   = @{}  # id → edge object
$EdgeSeq = 0

function Add-Node {
  param([string]$Label, [string]$Type, [hashtable]$Attributes = @{}, [string]$Evidence = "", [float]$Confidence = 1.0)

  if (-not $Label -or $Label.Length -lt 2) { return $null }

  $id = Make-NodeId -Label $Label -Type $Type

  if (-not $Nodes.ContainsKey($id)) {
    $Nodes[$id] = @{
      id         = $id
      type       = $Type
      label      = $Label
      attributes = $Attributes
      evidence   = @()
      confidence = $Confidence
      domain     = $Domain
    }
  }

  if ($Evidence -and ($Nodes[$id].evidence -notcontains $Evidence)) {
    $Nodes[$id].evidence += $Evidence
  }

  return $id
}

function Add-Edge {
  param(
    [string]$FromId, [string]$ToId,
    [string]$Rel, [string]$RelType,
    [hashtable]$Attrs = @{},
    [string]$Evidence = "",
    [float]$Confidence = 0.8
  )

  if (-not $FromId -or -not $ToId -or $FromId -eq $ToId) { return }

  # Canonical edge key — prevents duplicates for same pair+relationship
  $key = "$FromId|$Rel|$ToId"
  if ($Edges.ContainsKey($key)) {
    # Merge evidence
    if ($Evidence -and ($Edges[$key].evidence -notcontains $Evidence)) {
      $Edges[$key].evidence += $Evidence
      $Edges[$key].confidence = [Math]::Min(1.0, $Edges[$key].confidence + 0.05)
    }
    return
  }

  $script:EdgeSeq++
  $edgeObj = @{
    id           = "edge_{0:D4}" -f $script:EdgeSeq
    from         = $FromId
    to           = $ToId
    relationship = $Rel
    rel_type     = $RelType
    evidence     = @()
    confidence   = $Confidence
  }
  foreach ($k in $Attrs.Keys) { $edgeObj[$k] = $Attrs[$k] }
  if ($Evidence) { $edgeObj.evidence += $Evidence }

  $Edges[$key] = $edgeObj
}

# ---------------------------------------------------------------------------
# GEDCOM EXPORT
# ---------------------------------------------------------------------------

function Export-Gedcom {
  param([string]$OutPath)

  $lines = @()
  $lines += "0 HEAD"
  $lines += "1 SOUR CIC_ERG"
  $lines += "1 GEDC"
  $lines += "2 VERS 5.5.1"
  $lines += "2 FORM LINEAGE-LINKED"
  $lines += "1 CHAR UTF-8"
  $lines += "1 DATE $(Get-Date -Format 'dd MMM yyyy').ToUpper()"

  # Assign GEDCOM IDs to person nodes
  $personIdx = @{}
  $familyIdx = @{}
  $pSeq = 0; $fSeq = 0

  foreach ($node in ($Nodes.Values | Where-Object { $_.type -eq "Person" })) {
    $pSeq++
    $gedId = "@I{0:D4}@" -f $pSeq
    $personIdx[$node.id] = $gedId

    $lines += "0 $gedId INDI"
    # Name in GEDCOM format: First /Surname/
    $parts = $node.label -split '\s+'
    if ($parts.Count -ge 2) {
      $surname = $parts[-1]
      $given   = ($parts[0..($parts.Count-2)]) -join " "
      $lines += "1 NAME $given /$surname/"
      $lines += "2 GIVN $given"
      $lines += "2 SURN $surname"
    } else {
      $lines += "1 NAME $($node.label)"
    }

    # Birth
    if ($node.attributes.birth_date) {
      $lines += "1 BIRT"
      $lines += "2 DATE $($node.attributes.birth_date)"
      if ($node.attributes.birth_place) { $lines += "2 PLAC $($node.attributes.birth_place)" }
    }
    # Death
    if ($node.attributes.death_date) {
      $lines += "1 DEAT"
      $lines += "2 DATE $($node.attributes.death_date)"
      if ($node.attributes.death_place) { $lines += "2 PLAC $($node.attributes.death_place)" }
    }
  }

  # Family units from spouse_of and parent_of edges
  $spouseEdges = $Edges.Values | Where-Object { $_.relationship -eq "spouse_of" }
  foreach ($e in $spouseEdges) {
    $fSeq++
    $famId = "@F{0:D4}@" -f $fSeq
    $h = $personIdx[$e.from]
    $w = $personIdx[$e.to]
    if (-not $h -or -not $w) { continue }
    $familyIdx["$($e.from)|$($e.to)"] = $famId
    $familyIdx["$($e.to)|$($e.from)"] = $famId

    $lines += "0 $famId FAM"
    $lines += "1 HUSB $h"
    $lines += "1 WIFE $w"
  }

  # Add children to families
  $parentEdges = $Edges.Values | Where-Object { $_.relationship -eq "parent_of" }
  # Group children by parent-pair
  $childMap = @{}
  foreach ($e in $parentEdges) {
    # Find the family this parent belongs to
    foreach ($fKey in $familyIdx.Keys) {
      if ($fKey -match "^$([regex]::Escape($e.from))\|") {
        $famId = $familyIdx[$fKey]
        if (-not $childMap[$famId]) { $childMap[$famId] = @() }
        if ($personIdx[$e.to] -and $childMap[$famId] -notcontains $personIdx[$e.to]) {
          $childMap[$famId] += $personIdx[$e.to]
        }
      }
    }
  }
  # Inject CHIL lines into family records
  foreach ($famId in $childMap.Keys) {
    foreach ($childGedId in $childMap[$famId]) {
      $lines += "0 $famId FAM"  # re-opens to add child — real GEDCOM needs single block; flag for manual merge
      $lines += "1 CHIL $childGedId"
    }
  }

  $lines += "0 TRLR"
  $lines | Set-Content $OutPath -Encoding UTF8
  Write-Log "GEDCOM written: $OutPath ($($lines.Count) lines, $pSeq persons, $fSeq families)"
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

Write-Log "========== ENTITY GRAPH BUILD START =========="
Write-Log "Domain: $Domain | InputPath: $InputPath"

if (-not (Test-Path $InputPath)) {
  Write-Log "ERROR: InputPath does not exist: $InputPath"
  exit 1
}

if (-not (Test-Path $OutputPath)) {
  New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Set alias table
$AliasTable = if ($Domain -eq 'documentary') { $AliasTable_Documentary } else { @{} }

# Load genealogy config if applicable
$GenealogyConfig = $null
if ($Domain -eq 'genealogy') {
  $cfgPath = if ($ConfigFile -and (Test-Path $ConfigFile)) { $ConfigFile } else {
    "$RootPath\metadata\genealogy_config.json"
  }
  if (Test-Path $cfgPath) {
    $GenealogyConfig = Get-Content $cfgPath -Raw | ConvertFrom-Json
    Write-Log "Loaded genealogy config: $($GenealogyConfig.client_name)"
    # Extend alias table with configured surnames
    foreach ($line in $GenealogyConfig.family_lines) {
      foreach ($surname in $line.surnames) {
        # no generic alias needed; full names stay as-is
      }
    }
  }
}

# --- Step 1: Seed documentary facts ---
if ($Domain -eq 'documentary') {
  Write-Log "Seeding Sorensen network facts..."
  foreach ($fact in (Get-DocumentarySeedFacts)) {
    $fromId = Add-Node -Label $fact.from -Type $fact.from_type -Confidence 1.0
    $toId   = Add-Node -Label $fact.to   -Type $fact.to_type   -Confidence 1.0

    $attrs = @{}
    if ($fact.start) { $attrs['start_date'] = $fact.start }
    if ($fact.end)   { $attrs['end_date']   = $fact.end   }
    if ($fact.note)  { $attrs['note']       = $fact.note  }

    Add-Edge -FromId $fromId -ToId $toId -Rel $fact.rel -RelType $fact.rel_type `
             -Attrs $attrs -Evidence "seed" -Confidence $fact.confidence
  }
  Write-Log "  Seeded: $($Nodes.Count) nodes, $($Edges.Count) edges"
}

# --- Step 2: Process sidecars ---
$sidecars = @(Get-ChildItem -Path $InputPath -Filter "*.json" -ErrorAction SilentlyContinue)
Write-Log "Processing $($sidecars.Count) sidecar files..."

foreach ($sidecar in $sidecars) {
  try {
    $json    = Get-Content $sidecar.FullName -Raw | ConvertFrom-Json
    $docId   = if ($json.filename) { $json.filename } else { $sidecar.BaseName }
    $docType = if ($json.classification) { $json.classification.type } else { "Unknown" }
    $ocrText = if ($json.content_description.ocr_text) { $json.content_description.ocr_text } else { "" }

    Write-Log "  $docId ($docType)"

    # Add Document node
    $docNodeId = Add-Node -Label $docId -Type "Document" -Attributes @{
      doc_type = $docType
      date     = if ($json.classification) { $json.classification.historical_date } else { "" }
      topic    = if ($json.classification) { $json.classification.primary_topic }   else { "" }
    } -Confidence 1.0

    # Collect entity sets
    $ents = $json.content_description.entities_identified
    $peopleRaw = @(); $placesRaw = @(); $orgsRaw = @()
    if ($ents) {
      if ($ents.people)        { $peopleRaw = @($ents.people) }
      if ($ents.places)        { $placesRaw = @($ents.places) }
      if ($ents.organizations) { $orgsRaw   = @($ents.organizations) }
    }

    # Resolve and add Person nodes (with type-override for misclassified orgs/places)
    $personIds = @()
    foreach ($raw in $peopleRaw) {
      $name = Resolve-Name -Raw $raw -Aliases $AliasTable
      if (-not $name) { continue }
      $inferredType = Infer-EntityType -Label $name -DefaultType "Person"
      $nid = Add-Node -Label $name -Type $inferredType -Evidence $docId
      if ($nid -and $inferredType -eq "Person") { $personIds += $nid }
    }

    # Resolve and add Place nodes
    $placeIds = @()
    foreach ($raw in $placesRaw) {
      $name = Resolve-Name -Raw $raw -Aliases $AliasTable
      if (-not $name) { continue }
      $nid = Add-Node -Label $name -Type "Place" -Evidence $docId
      if ($nid) { $placeIds += $nid }
    }

    # Resolve and add Organization nodes
    $orgIds = @()
    foreach ($raw in $orgsRaw) {
      $name = Resolve-Name -Raw $raw -Aliases $AliasTable
      if (-not $name) { continue }
      $nid = Add-Node -Label $name -Type "Organization" -Evidence $docId
      if ($nid) { $orgIds += $nid }
    }

    # Vital record relationship extraction (genealogy + documentary)
    $vitalRels = Parse-VitalRecordRelationships -OcrText $ocrText -DocType $docType -DocId $docId
    foreach ($vr in $vitalRels) {
      $fName = Resolve-Name -Raw $vr.from -Aliases $AliasTable
      $tName = Resolve-Name -Raw $vr.to   -Aliases $AliasTable
      if (-not $fName -or -not $tName) { continue }

      $fId = Add-Node -Label $fName -Type $vr.from_type -Evidence $docId
      $tId = Add-Node -Label $tName -Type $vr.to_type   -Evidence $docId

      $attrs = @{}
      if ($vr.parent_role) { $attrs['parent_role'] = $vr.parent_role }
      if ($vr.note)        { $attrs['note']        = $vr.note }

      Add-Edge -FromId $fId -ToId $tId -Rel $vr.rel -RelType $vr.rel_type `
               -Attrs $attrs -Evidence $docId -Confidence $vr.confidence
    }

    # Co-occurrence edges: persons in same document → associated_with
    $allEntIds = @($personIds) + @($orgIds)
    for ($i = 0; $i -lt $allEntIds.Count; $i++) {
      for ($j = $i+1; $j -lt $allEntIds.Count; $j++) {
        Add-Edge -FromId $allEntIds[$i] -ToId $allEntIds[$j] `
                 -Rel "associated_with" -RelType "associative" `
                 -Evidence $docId -Confidence 0.5
      }
      # Person/Org → places they appear with
      foreach ($plId in $placeIds) {
        Add-Edge -FromId $allEntIds[$i] -ToId $plId `
                 -Rel "associated_with" -RelType "geographic" `
                 -Evidence $docId -Confidence 0.5
      }
    }

    # Document → entities (document mentions)
    foreach ($nid in ($personIds + $placeIds + $orgIds)) {
      Add-Edge -FromId $docNodeId -ToId $nid -Rel "mentions" -RelType "documentary" `
               -Evidence $docId -Confidence 1.0
    }

  } catch {
    Write-Log "  ERROR processing $($sidecar.Name): $_"
  }
}

# --- Step 3: Output graph JSON ---
$graph = @{
  generated     = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  domain        = $Domain
  source        = $InputPath
  node_count    = $Nodes.Count
  edge_count    = $Edges.Count
  nodes         = @($Nodes.Values)
  edges         = @($Edges.Values)
}

$graphPath = "$OutputPath\entity_graph.json"
$graph | ConvertTo-Json -Depth 8 | Set-Content $graphPath -Encoding UTF8
Write-Log "Graph saved: $graphPath ($($Nodes.Count) nodes, $($Edges.Count) edges)"

# --- Step 4: GEDCOM export (genealogy mode) ---
if ($Domain -eq 'genealogy') {
  $gedPath = "$OutputPath\entity_graph.ged"
  Export-Gedcom -OutPath $gedPath
}

# --- Step 5: Markdown summary ---
$summaryLines = @(
  "# Entity Relationship Graph Summary",
  "",
  "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
  "**Domain:** $Domain",
  "**Source:** $InputPath",
  "",
  "## Counts",
  "",
  "| Type | Count |",
  "|------|-------|"
)
foreach ($t in @("Person","Place","Organization","Document","Event")) {
  $c = ($Nodes.Values | Where-Object { $_.type -eq $t }).Count
  if ($c -gt 0) { $summaryLines += "| $t | $c |" }
}
$summaryLines += "| **Total nodes** | **$($Nodes.Count)** |"
$summaryLines += "| **Total edges** | **$($Edges.Count)** |"

$summaryLines += @("", "## People", "")
foreach ($n in ($Nodes.Values | Where-Object { $_.type -eq "Person" } | Sort-Object { $_.label })) {
  $edgeList = $Edges.Values | Where-Object { $_.from -eq $n.id -and $_.relationship -ne "associated_with" -and $_.relationship -ne "mentions" }
  $relSummary = ($edgeList | ForEach-Object { "$($_.relationship) → $($Nodes[$_.to].label)" }) -join "; "
  $docs = ($n.evidence | Where-Object { $_ -ne "seed" }) -join ", "
  $summaryLines += "**$($n.label)**"
  if ($relSummary) { $summaryLines += "- Relationships: $relSummary" }
  if ($docs)       { $summaryLines += "- Evidence: $docs" }
  $summaryLines += ""
}

$summaryLines += @("## Key Relationships", "")
$keyRels = $Edges.Values | Where-Object { $_.rel_type -in @("family","organizational") -and $_.relationship -ne "associated_with" } |
           Sort-Object confidence -Descending | Select-Object -First 25
foreach ($e in $keyRels) {
  $fromLabel = if ($Nodes[$e.from]) { $Nodes[$e.from].label } else { $e.from }
  $toLabel   = if ($Nodes[$e.to])   { $Nodes[$e.to].label   } else { $e.to   }
  $conf      = [math]::Round($e.confidence * 100)
  $summaryLines += "- **$fromLabel** → [$($e.relationship)] → **$toLabel** ($conf% confidence)"
}

$summaryPath = "$OutputPath\entity_graph_summary.md"
$summaryLines | Set-Content $summaryPath -Encoding UTF8
Write-Log "Summary written: $summaryPath"

Write-Log "========== ENTITY GRAPH BUILD COMPLETE =========="
Write-Host "`n✓ ENTITY GRAPH SUCCESS" -ForegroundColor Green
Write-Host "  Nodes: $($Nodes.Count) | Edges: $($Edges.Count)"
Write-Host "  Graph:   $graphPath"
Write-Host "  Summary: $summaryPath"
if ($Domain -eq 'genealogy') { Write-Host "  GEDCOM:  $gedPath" }
