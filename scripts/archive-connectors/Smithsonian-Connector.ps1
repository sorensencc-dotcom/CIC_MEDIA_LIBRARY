<#
  Smithsonian Open Access API — free, no auth required.
  Covers: NASM, NMAH, Smithsonian Archives, National Portrait Gallery, and 18 other units.
  Endpoint: https://api.si.edu/openaccess/api/v1.0/search
  Docs: https://edan.si.edu/openaccess/apidocs/
#>

$script:ConnectorRegistry += @{
  Name           = "Smithsonian"
  DisplayName    = "Smithsonian Open Access (incl. NASM)"
  Domains        = @("documentary","genealogy")
  RequiresAuth   = $false
  RateLimitMs    = 500
  Invoke         = {
    param([string]$Query, [hashtable]$Filters, [int]$MaxResults)

    $params = @{
      q       = $Query
      rows    = [Math]::Min($MaxResults, 20)
      start   = 0
      api_key = "DEMO_KEY"   # works for low-volume; replace with real key at api.data.gov
    }
    if ($Filters.unit) {
      $params["unit_code"] = $Filters.unit   # e.g. "NASM" to scope to Air & Space
    }

    $uri = "https://api.si.edu/openaccess/api/v1.0/search?" + (
      $params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" } | Join-String -Separator "&"
    )

    $resp = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 30 -ErrorAction Stop
    $results = @()

    foreach ($row in $resp.response.rows) {
      $content = $row.content
      $desc    = $content.descriptiveNonRepeating
      $indexed = $content.indexedStructured
      $free    = $content.freetext

      $date = ""
      if ($indexed.date)        { $date = ($indexed.date | Select-Object -First 1) }
      elseif ($free.date)       { $date = ($free.date.content | Select-Object -First 1) }

      $format = "document"
      if ($desc.online_media) {
        $mt = ($desc.online_media.media | Select-Object -First 1)
        if ($mt) {
          $format = switch -Wildcard ($mt.type) {
            "*Images*"  { "photograph" }
            "*Videos*"  { "film" }
            "*Audio*"   { "audio" }
            default     { "document" }
          }
        }
      }

      $thumbUrl = ""
      if ($desc.online_media.media) {
        $m = $desc.online_media.media | Select-Object -First 1
        if ($m.thumbnail) { $thumbUrl = $m.thumbnail }
      }

      $results += @{
        result_id        = "si_$($row.id -replace '[^a-zA-Z0-9]','_')"
        source_archive   = "Smithsonian ($($desc.data_source))"
        source_connector = "Smithsonian"
        title            = $desc.title.content
        description      = if ($free.notes) { ($free.notes.content -join " ") } else { "" }
        date             = $date
        url              = $desc.record_link
        thumbnail        = $thumbUrl
        format           = $format
        rights           = if ($desc.rights) { $desc.rights.usage.access } else { "See source" }
        subject          = if ($indexed.topic) { $indexed.topic } else { @() }
        relevance_score  = 0.6
      }
    }
    return $results
  }
}
