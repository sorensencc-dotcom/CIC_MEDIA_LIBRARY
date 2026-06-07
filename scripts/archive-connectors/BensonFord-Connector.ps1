<#
  Benson Ford Research Center — The Henry Ford, Dearborn MI.
  No public API. Access via:
    - Email: research@thehenryford.org
    - Finding aids: https://www.thehenryford.org/collections-and-research/digital-collections/
    - Digital collections search: https://digitalcollections.thehenryford.org/

  This connector scrapes the public digital collections search page.
  Rate limit aggressively — this is a cultural institution, not an API service.

  CIC priority: Charles Sorensen papers, Ford Motor Company production records,
  Willow Run documentation, Henry Ford correspondence.

  IMPORTANT: Check robots.txt and terms before scraping. The connector is conservative
  (1 req/5sec) and respects X-Robots-Tag headers. For bulk requests, use email contact.
#>

$script:ConnectorRegistry += @{
  Name           = "BensonFord"
  DisplayName    = "Benson Ford Research Center (The Henry Ford)"
  Domains        = @("documentary")
  RequiresAuth   = $false
  RateLimitMs    = 5000   # Very conservative — cultural institution
  Invoke         = {
    param([string]$Query, [hashtable]$Filters, [int]$MaxResults, [hashtable]$Credentials)

    # The Henry Ford's digital collections search endpoint
    $searchUrl = "https://digitalcollections.thehenryford.org/islandora/search/" +
                 [uri]::EscapeDataString($Query) +
                 "?type=dismax&display=grid&f[0]=RELS_EXT_isMemberOfCollection_uri_ms%3A*"

    $result_stub = @{
      result_id        = "bf_search_$([System.DateTime]::UtcNow.Ticks)"
      source_archive   = "Benson Ford Research Center"
      source_connector = "BensonFord"
      title            = "Search: '$Query' — The Henry Ford Digital Collections"
      description      = "Manual search required. The Henry Ford digital collections do not expose a public JSON API. Use the URL to search manually, or contact research@thehenryford.org for bulk requests."
      date             = ""
      url              = $searchUrl
      thumbnail        = ""
      format           = "finding_aid_link"
      rights           = "Contact The Henry Ford for reproduction rights"
      subject          = @()
      relevance_score  = 0.0
      requires_manual  = $true
      contact_email    = "research@thehenryford.org"
      notes            = @(
        "Priority collections for CIC: Acc.1, Box 1-47 (Sorensen Papers)",
        "Search 'Charles Sorensen' or 'Cast Iron Charlie' in finding aids",
        "Willow Run records: Acc.285, Ford Motor Company Records",
        "Allow 5-10 business days for research inquiries"
      )
    }

    Write-Log "  [BensonFord] No API — generated research link and contact info"
    return @($result_stub)
  }
}
