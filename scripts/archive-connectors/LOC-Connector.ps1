<#
  Library of Congress — open API, no auth required.
  Endpoint: https://www.loc.gov/search/?q={query}&fo=json
  Docs: https://www.loc.gov/apis/json-and-yaml/
#>

$script:ConnectorRegistry += @{
  Name           = "LOC"
  DisplayName    = "Library of Congress"
  Domains        = @("documentary","genealogy")
  RequiresAuth   = $false
  RateLimitMs    = 1000   # 1 req/sec to be polite
  Invoke         = {
    param([string]$Query, [hashtable]$Filters, [int]$MaxResults)

    $baseUrl = "https://www.loc.gov/search/"
    $params  = @{
      q       = $Query
      fo      = "json"
      at      = "results,pagination"
      "c"     = [Math]::Min($MaxResults, 25)
      sp      = 1
    }
    if ($Filters.date_from -or $Filters.date_to) {
      $from = if ($Filters.date_from) { $Filters.date_from } else { "1800" }
      $to   = if ($Filters.date_to)   { $Filters.date_to   } else { "2026" }
      $params["dates"] = "$from/$to"
    }

    $uri = $baseUrl + "?" + (($params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }) -join "&")

    $resp = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 30 -ErrorAction Stop
    $results = @()

    foreach ($item in $resp.results) {
      $date = ""
      if ($item.date)       { $date = $item.date }
      elseif ($item.dates)  { $date = ($item.dates | Select-Object -First 1) }

      $format = "document"
      if ($item.original_format) {
        $of = ($item.original_format -join " ").ToLower()
        if ($of -match "photo|image|picture")     { $format = "photograph" }
        elseif ($of -match "map")                 { $format = "map" }
        elseif ($of -match "film|video|moving")   { $format = "film" }
        elseif ($of -match "audio|sound|record")  { $format = "audio" }
        elseif ($of -match "manuscript|letter")   { $format = "correspondence" }
        elseif ($of -match "newspaper|periodical"){ $format = "newspaper" }
      }

      $results += @{
        result_id      = "loc_$($item.id -replace '[^a-zA-Z0-9]','_')"
        source_archive = "Library of Congress"
        source_connector = "LOC"
        title          = $item.title
        description    = if ($item.description) { ($item.description -join " ") } else { "" }
        date           = $date
        url            = $item.url
        thumbnail      = if ($item.image_url) { $item.image_url[0] } else { "" }
        format         = $format
        rights         = if ($item.rights) { $item.rights } else { "See source for rights information" }
        subject        = if ($item.subject) { $item.subject } else { @() }
        relevance_score = if ($item.score) { [float]$item.score } else { 0.5 }
      }
    }
    return $results
  }
}
