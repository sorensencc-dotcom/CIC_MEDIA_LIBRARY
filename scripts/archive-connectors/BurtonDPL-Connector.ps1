<#
  Detroit Public Library — Burton Historical Collection.
  No public REST API. Access via detroitpubliclibrary.org.
  CIC relevance: HIGH — primary repository for Detroit automotive/labor history,
                 Ford Motor Company newspaper coverage, Michigan manufacturing records.

  Burton Historical Collection is DPL's flagship special collections unit.
  Holds: Detroit newspapers (1837–present), automotive industry records, Michigan biography,
         Great Lakes history, manuscript collections, maps, photographs.

  Key holdings for CIC:
    - Detroit Free Press and Detroit News archives (Ford coverage 1903–1960)
    - Michigan Manufacturer and Financial Record (trade publication)
    - Automotive history manuscripts
    - UAW/labor union records (joint custody with Wayne State's ALUA)
    - Ford family biographical files
    - Willow Run-area local history (Ypsilanti)

  Digital access:
    - DPL Digital Collections: detroitpubliclibrary.org (search: "Digital Collection" tab)
    - Michigan eLibrary (MeL): mel.org — statewide digital resource
    - Burton finding aids: detroitpubliclibrary.org/collections/burton

  Contact:
    - Burton Historical Collection: (313) 481-1488 | burton@detroitpubliclibrary.org
    - Main DPL: (313) 481-1300
    - In-person: 5201 Woodward Ave, Detroit MI 48202
#>

$script:ConnectorRegistry += @{
  Name           = "BurtonDPL"
  DisplayName    = "Detroit Public Library — Burton Historical Collection"
  Domains        = @("documentary","genealogy")
  RequiresAuth   = $false
  RateLimitMs    = 0
  Invoke         = {
    param([string]$Query, [hashtable]$Filters, [int]$MaxResults, [hashtable]$Credentials)

    $encodedQuery = [uri]::EscapeDataString($Query)

    # DPL digital collection search (embedded in main site)
    $dplDigitalUrl  = "https://www.detroitpubliclibrary.org/?s=$encodedQuery&search_type=digital"
    $burtonUrl      = "https://www.detroitpubliclibrary.org/collections/burton-historical-collection"

    # Michigan eLibrary — statewide digital resource (DPL participates)
    $melUrl         = "https://mel.org/search?q=$encodedQuery"

    # ALUA (Archives of Labor and Urban Affairs, Wayne State) — holds UAW records relevant to Ford/Willow Run
    $aluaUrl        = "https://reuther.wayne.edu/search-collections?q=$encodedQuery"

    # Newspaper archive links — key for Ford coverage
    $chroniclingUrl = "https://www.loc.gov/collections/chronicling-america/?q=$encodedQuery&fa=location_state:michigan"

    # CIC-priority collections within Burton
    $cicPriorityCollections = @(
      @{
        label = "Detroit Free Press morgue (Ford coverage 1903–1960)"
        url   = "https://www.detroitpubliclibrary.org/collections/burton-historical-collection"
        note  = "DFP morgue files include clippings on Ford Motor Company, Sorensen, Willow Run. Accessible in Burton reading room — call ahead."
      },
      @{
        label = "Michigan Manufacturer and Financial Record"
        url   = "https://hathitrust.org/search?q=$encodedQuery&facet=date_start&fq[]=date_start%3A%5B1930+TO+1960%5D"
        note  = "Trade publication covering Michigan manufacturing 1888–1940s. Digitized on HathiTrust. Covers Ford production statistics and executive profiles."
      },
      @{
        label = "ALUA — UAW Records (Reuther Library, Wayne State)"
        url   = $aluaUrl
        note  = "Archives of Labor and Urban Affairs holds UAW local records from River Rouge and Willow Run plants. Key for labor-management context of Sorensen era."
      },
      @{
        label = "Michigan Chronicling America newspapers"
        url   = $chroniclingUrl
        note  = "LOC Chronicling America filtered to Michigan — Detroit Free Press 1880s–1920s, other Michigan papers. Free, no registration."
      }
    )

    $results = @()

    # Primary search link
    $results += @{
      result_id        = "dpl_search_$([System.DateTime]::UtcNow.Ticks)"
      source_archive   = "Detroit Public Library — Burton Historical Collection"
      source_connector = "BurtonDPL"
      title            = "Burton Historical Collection Search: '$Query'"
      description      = "DPL Burton Historical Collection — primary repository for Detroit automotive, labor, and Michigan history. No public API; access via reading room or digital collection search."
      date             = ""
      url              = $burtonUrl
      thumbnail        = ""
      format           = "finding_aid_link"
      rights           = "Varies by item — most public domain, some restricted"
      subject          = @()
      relevance_score  = 0.0
      requires_manual  = $true
      contact_email    = "burton@detroitpubliclibrary.org"
      notes            = @(
        "Phone: (313) 481-1488 — call ahead for reading room access",
        "Address: 5201 Woodward Ave, Detroit MI 48202",
        "Hours: Tue–Sat 9:30am–5:30pm (verify before visiting)",
        "Digital collection search: detroitpubliclibrary.org → 'Digital Collection' tab",
        "Michigan eLibrary (mel.org) provides remote access to some DPL digital holdings"
      )
    }

    # CIC-priority collections
    foreach ($col in $cicPriorityCollections) {
      $results += @{
        result_id        = "dpl_$($col.label -replace '[^a-zA-Z0-9]','_' -replace '_+','_' | ForEach-Object { $_.Substring(0,[Math]::Min(40,$_.Length)) })"
        source_archive   = "Burton/DPL — $($col.label)"
        source_connector = "BurtonDPL"
        title            = $col.label
        description      = $col.note
        date             = ""
        url              = $col.url
        thumbnail        = ""
        format           = "finding_aid_link"
        rights           = "Varies"
        subject          = @("Detroit","Ford Motor Company","Michigan","automotive history")
        relevance_score  = 0.0
        requires_manual  = $true
      }
    }

    Write-Log "  [BurtonDPL] No API — generated $($results.Count) research links (Burton + ALUA + Michigan newspapers)"
    return $results
  }
}
