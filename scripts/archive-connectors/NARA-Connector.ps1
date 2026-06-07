<#
  National Archives and Records Administration (NARA).
  No public JSON API available as of 2025 — catalog.archives.gov is a React SPA.

  Access via:
    - Catalog search: https://catalog.archives.gov/search
    - OPA Bulk Data: https://www.archives.gov/developer (bulk download datasets)
    - FOIA requests for restricted records: https://www.archives.gov/foia

  CIC priority records:
    - Willow Run Bomber Plant: RG 179 (War Production Board), RG 18 (Army Air Forces)
    - Ford Motor Company WWII contracts: RG 179, RG 169 (Foreign Economic Administration)
    - Charles Sorensen — likely in Ford-related collection finding aids
    - B-24 Liberator production: RG 18, RG 342 (Air Force Command)
    - War Production Board minutes: RG 179

  This connector generates targeted search links and FOIA guidance for CIC researchers.
#>

$script:ConnectorRegistry += @{
  Name           = "NARA"
  DisplayName    = "National Archives (NARA)"
  Domains        = @("documentary","genealogy")
  RequiresAuth   = $false
  RateLimitMs    = 0
  Invoke         = {
    param([string]$Query, [hashtable]$Filters, [int]$MaxResults, [hashtable]$Credentials)

    $encodedQuery = [uri]::EscapeDataString($Query)
    $catalogUrl   = "https://catalog.archives.gov/search?q=$encodedQuery&f.type=item"
    if ($Filters.date_from -or $Filters.date_to) {
      $from = if ($Filters.date_from) { $Filters.date_from } else { "1700" }
      $to   = if ($Filters.date_to)   { $Filters.date_to   } else { "2030" }
      $catalogUrl += "&f.dateRange=$from-$to"
    }

    # CIC-specific record groups (always relevant to Sorensen/Ford/Willow Run)
    $cicPriorityRGs = @(
      @{ rg="RG 179"; name="War Production Board";        scope="Willow Run contracts, B-24 authorization, Ford production targets 1942-1945" },
      @{ rg="RG 18";  name="Army Air Forces";              scope="B-24 Liberator production, Willow Run acceptance records, 1942-1945" },
      @{ rg="RG 342"; name="Air Force Command (USAF)";     scope="Post-war B-24 records, procurement history" },
      @{ rg="RG 169"; name="Foreign Economic Administration"; scope="Ford war production exports, Lend-Lease" }
    )

    $genealogyRGs = @(
      @{ rg="RG 29";  name="Bureau of the Census";         scope="Census records 1790-1940 (1950 released 2022)" },
      @{ rg="RG 85";  name="Immigration and Naturalization"; scope="Immigration, naturalization, passenger lists" },
      @{ rg="RG 15";  name="Veterans Administration";       scope="Military pension files, service records" },
      @{ rg="RG 407"; name="Adjutant General";              scope="WWI/WWII service records (if not destroyed in 1973 fire)" }
    )

    $results = @()

    # Main catalog search link
    $results += @{
      result_id        = "nara_search_$([System.DateTime]::UtcNow.Ticks)"
      source_archive   = "National Archives (NARA)"
      source_connector = "NARA"
      title            = "NARA Catalog Search: '$Query'"
      description      = "NARA Catalog search link. The catalog has no public JSON API; use the URL to search manually or download bulk data from archives.gov/developer."
      date             = ""
      url              = $catalogUrl
      thumbnail        = ""
      format           = "finding_aid_link"
      rights           = "US Government records — most are public domain; some restricted"
      subject          = @()
      relevance_score  = 0.0
      requires_manual  = $true
      contact_email    = "inquire@nara.gov"
    }

    # CIC priority record groups
    foreach ($rg in $cicPriorityRGs) {
      $rgUrl = "https://catalog.archives.gov/search?q=$encodedQuery&f.recordGroupNumber=$($rg.rg -replace 'RG ','')"
      $results += @{
        result_id        = "nara_rg_$($rg.rg -replace '[^a-z0-9]','_' -replace '_+','_')"
        source_archive   = "NARA — $($rg.rg): $($rg.name)"
        source_connector = "NARA"
        title            = "$($rg.rg) — $($rg.name)"
        description      = $rg.scope
        date             = ""
        url              = $rgUrl
        thumbnail        = ""
        format           = "finding_aid_link"
        rights           = "US Government records — public domain"
        subject          = @()
        relevance_score  = 0.0
        requires_manual  = $true
      }
    }

    Write-Log "  [NARA] No API — generated $($results.Count) catalog and record-group links"
    return $results
  }
}
