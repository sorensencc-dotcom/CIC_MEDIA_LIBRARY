<#
  Rigsarkivet (Danish National Archives) — no public REST API.
  Access via: sa.dk (registration required for full access), ao.sa.dk (authenticated)
  CIC relevance: CRITICAL — Charles Emil Sorensen born Odense, Denmark, 7 Apr 1881.
                 Emigrated to USA ~1885 with family.

  Key record types for Sorensen research:
    - Kirkebøger (church books): baptism, confirmation, marriage at Odense parishes
    - Emigrantprotokol (emigrant registers): 1868–1940, tracks departures by name/date/ship
    - Folkeregister (population register): Odense city records
    - Landsarkivet for Fyn: regional archive for Funen (Fyn) island where Odense sits

  Online access paths:
    - Arkivalieronline (ao.sa.dk): digitized records, free registration required
    - Arkivfundet (sa.dk search): finding aids and catalog
    - FamilySearch (our other connector) has many Danish records too

  Key institutions:
    - Rigsarkivet Copenhagen: rigsarkivet@sa.dk | +45 41 71 74 00
    - Odense Stadsarkiv (Odense City Archive): stadsarkiv@odense.dk | covers city records
    - Landsarkivet for Fyn (now part of Rigsarkivet): Odense regional collections
#>

$script:ConnectorRegistry += @{
  Name           = "Rigsarkivet"
  DisplayName    = "Rigsarkivet (Danish National Archives)"
  Domains        = @("documentary","genealogy")
  RequiresAuth   = $false
  RateLimitMs    = 0
  Invoke         = {
    param([string]$Query, [hashtable]$Filters, [int]$MaxResults, [hashtable]$Credentials)

    $encodedQuery = [uri]::EscapeDataString($Query)

    # Construct targeted search URLs for the query
    $aoSearchUrl       = "https://ao.sa.dk/ao/?q=$encodedQuery"
    $odenseArchiveUrl  = "https://www.odense.dk/borger/kultur-og-fritid/stadsarkivet"
    $familySearchDkUrl = "https://www.familysearch.org/search/collection/list?q=$encodedQuery&f.regionCountry=denmark"

    # Sorensen-specific record paths (CIC priority)
    $sorensenRecords = @(
      @{
        label = "Emigrantprotokol 1880–1886 (Sorensen family departure)"
        url   = "https://ao.sa.dk/ao/?q=sorensen+odense&f=emigrant"
        note  = "Charles Emil Sorensen born 7 Apr 1881 Odense; family emigrated ~1885. Search emigrant registers for Sorensen/Sørensen in Odense, Fyn."
      },
      @{
        label = "Kirkebøger — Odense parishes (baptism 1881)"
        url   = "https://ao.sa.dk/ao/?q=sørensen+odense+1881&f=kirkebog"
        note  = "Baptism record likely at Vor Frue Kirke or Sankt Knuds Kirke, Odense. Search Fyn Stift kirkebøger 1875–1890."
      },
      @{
        label = "Folkeregister Odense (population register)"
        url   = "https://ao.sa.dk/ao/?q=sørensen+odense+1881&f=folkeregister"
        note  = "Odense folkeregister shows household composition, birthplaces, occupations."
      },
      @{
        label = "FamilySearch — Denmark records"
        url   = "https://www.familysearch.org/search/record/results?q.surname=Sorensen&q.birthPlace=Denmark&q.birthDate=1881&q.birthDateRange=2"
        note  = "FamilySearch holds many Danish church records via digitization agreements with Rigsarkivet."
      }
    )

    $results = @()

    # Primary search link
    $results += @{
      result_id        = "da_search_$([System.DateTime]::UtcNow.Ticks)"
      source_archive   = "Rigsarkivet (Danish National Archives)"
      source_connector = "Rigsarkivet"
      title            = "Arkivalieronline Search: '$Query'"
      description      = "Free registration required at ao.sa.dk. Covers kirkebøger, emigrant registers, census, land records, probate. Danish UI — use 'Sørensen' (with ø) for Danish name variant."
      date             = ""
      url              = $aoSearchUrl
      thumbnail        = ""
      format           = "finding_aid_link"
      rights           = "Danish public records — free access with registration"
      subject          = @()
      relevance_score  = 0.0
      requires_manual  = $true
      contact_email    = "rigsarkivet@sa.dk"
      notes            = @(
        "Register free at https://ao.sa.dk/ for full record access",
        "Search both 'Sorensen' and 'Sørensen' (Danish ø variant)",
        "Landsarkivet for Fyn holds Odense city and Fyn regional records",
        "Contact Odense Stadsarkiv: stadsarkiv@odense.dk for city-level records",
        "Phone: +45 41 71 74 00 (English spoken — major institution)"
      )
    }

    # CIC-priority Sorensen records
    foreach ($rec in $sorensenRecords) {
      $results += @{
        result_id        = "da_$($rec.label -replace '[^a-zA-Z0-9]','_' -replace '_+','_' | ForEach-Object { $_.Substring(0,[Math]::Min(40,$_.Length)) })"
        source_archive   = "Rigsarkivet — $($rec.label)"
        source_connector = "Rigsarkivet"
        title            = $rec.label
        description      = $rec.note
        date             = ""
        url              = $rec.url
        thumbnail        = ""
        format           = "finding_aid_link"
        rights           = "Danish public records — free with registration"
        subject          = @("Charles Emil Sorensen","Odense","Denmark","emigration")
        relevance_score  = 0.0
        requires_manual  = $true
      }
    }

    Write-Log "  [Rigsarkivet] No API — generated $($results.Count) research links (Sorensen birth/emigration records)"
    return $results
  }
}
