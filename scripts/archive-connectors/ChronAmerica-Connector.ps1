<#
  Chronicling America — LOC's historic US newspaper archive.
  Free, no auth. Coverage: 1770–1963, 20M+ pages.
  Endpoint: https://www.loc.gov/collections/chronicling-america/ (LOC Collections API, fo=json)
  Note: The old chroniclingamerica.loc.gov/search/pages/results/ endpoint was retired.

  CIC use: Ford-era newspaper coverage (Detroit Free Press, Chicago Tribune, etc.)
  Genealogy use: Obituaries, birth announcements, immigration notices.
#>

$script:ConnectorRegistry += @{
  Name           = "ChronAmerica"
  DisplayName    = "Chronicling America (LOC Newspaper Archive)"
  Domains        = @("documentary","genealogy")
  RequiresAuth   = $false
  RateLimitMs    = 800
  Invoke         = {
    param([string]$Query, [hashtable]$Filters, [int]$MaxResults, [hashtable]$Credentials)

    $params = @{
      q  = $Query
      fo = "json"
      c  = [Math]::Min($MaxResults, 25)
      sp = 1
    }
    if ($Filters.date_from -or $Filters.date_to) {
      $from = if ($Filters.date_from) { $Filters.date_from } else { "1770" }
      $to   = if ($Filters.date_to)   { $Filters.date_to   } else { "1963" }
      $params["dates"] = "$from/$to"
    }
    if ($Filters.state) {
      $params["fa"] = "location_state:$($Filters.state.ToLower())"
    }

    $uri = "https://www.loc.gov/collections/chronicling-america/?" + (
      $params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" } | Join-String -Separator "&"
    )

    $resp    = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 30 -ErrorAction Stop
    $results = @()

    foreach ($item in $resp.results) {
      $imgUrl = ""
      if ($item.image_url) { $imgUrl = $item.image_url[0] }

      $stateStr = ""
      if ($item.location_state) { $stateStr = $item.location_state -join ", " }

      $partofName = ""
      if ($item.partof_title) { $partofName = $item.partof_title -join "; " }

      $results += @{
        result_id        = "chrona_$($item.id -replace '[^a-zA-Z0-9]','_')"
        source_archive   = "Chronicling America — $partofName"
        source_connector = "ChronAmerica"
        title            = $item.title
        description      = if ($item.description) { ($item.description -join " ") } else { "" }
        date             = $item.date
        url              = $item.url
        thumbnail        = $imgUrl
        format           = "newspaper"
        rights           = "Public Domain"
        subject          = if ($item.subject) { $item.subject } else { @() }
        relevance_score  = 0.6
        extra            = @{
          state      = $stateStr
          page       = if ($item.number_page)    { $item.number_page   } else { "" }
          edition    = if ($item.number_edition) { $item.number_edition } else { "" }
          lccn       = if ($item.number_lccn)    { $item.number_lccn   } else { "" }
          collection = if ($item.partof_collection) { $item.partof_collection } else { @() }
        }
      }
    }
    return $results
  }
}
