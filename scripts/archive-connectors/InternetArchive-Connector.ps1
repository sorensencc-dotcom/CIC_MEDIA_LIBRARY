<#
  Internet Archive (archive.org) — free, no auth required.
  28M+ items: books, films, audio, web archives, software, images.
  Endpoint: https://archive.org/advancedsearch.php (Solr-based, returns JSON)
  Docs: https://archive.org/advancedsearch.php (self-documenting)

  CIC use: Ford company films, B-24 documentation, WWII newsreels, trade publications,
           aviation periodicals, Willow Run footage, vintage Ford promotional materials.
  Genealogy use: Digitized newspapers, local histories, city directories, immigration records.

  Field list reference:
    identifier, title, description, date, mediatype, subject, creator, publisher,
    language, format, type, collection, licenseurl, avg_rating, downloads, year
#>

$script:ConnectorRegistry += @{
  Name           = "InternetArchive"
  DisplayName    = "Internet Archive (archive.org)"
  Domains        = @("documentary","genealogy")
  RequiresAuth   = $false
  RateLimitMs    = 600
  Invoke         = {
    param([string]$Query, [hashtable]$Filters, [int]$MaxResults, [hashtable]$Credentials)

    # Solr: do NOT quote multi-word queries — phrase search is too strict; unquoted terms require AND match
    $solrQ = $Query

    # Narrow to item-level records; exclude collections, accounts, etree
    $filter = "mediatype:(texts OR movies OR audio OR image)"
    if ($Filters.date_from -or $Filters.date_to) {
      $from = if ($Filters.date_from) { $Filters.date_from } else { "1800" }
      $to   = if ($Filters.date_to)   { $Filters.date_to   } else { "2030" }
      $filter += " AND year:[$from TO $to]"
    }

    # fl[] (with brackets) is the correct IA Solr parameter format
    $fieldList = "identifier,title,description,date,year,mediatype,subject,creator,publisher,licenseurl"

    $uri = "https://archive.org/advancedsearch.php?" + (
      @(
        "q=$([uri]::EscapeDataString("$solrQ AND $filter"))",
        "fl[]=$([uri]::EscapeDataString($fieldList))",
        "rows=$([Math]::Min($MaxResults, 50))",
        "page=1",
        "output=json",
        "sort=$([uri]::EscapeDataString("downloads desc"))"
      ) -join "&"
    )

    $resp    = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 30 -ErrorAction Stop
    $results = @()

    foreach ($doc in $resp.response.docs) {
      $format = switch ($doc.mediatype) {
        "texts"  { "document" }
        "movies" { "film" }
        "audio"  { "audio" }
        "image"  { "photograph" }
        default  { "document" }
      }

      $date = ""
      if ($doc.date) { $date = $doc.date -replace 'T.*','' }
      elseif ($doc.year) { $date = [string]$doc.year }

      $desc = ""
      if ($doc.description) {
        $desc = if ($doc.description -is [array]) { $doc.description[0] } else { $doc.description }
        if ($desc.Length -gt 500) { $desc = $desc.Substring(0, 500) + "..." }
      }

      $rights = "Public Domain"
      if ($doc.licenseurl) {
        if ($doc.licenseurl -match "licenses/by")  { $rights = "Creative Commons Attribution" }
        elseif ($doc.licenseurl -match "licenses/") { $rights = "Creative Commons — see $($doc.licenseurl)" }
      }

      $subjects = @()
      if ($doc.subject) {
        $subjects = if ($doc.subject -is [array]) { $doc.subject } else { @($doc.subject) }
      }

      $results += @{
        result_id        = "ia_$($doc.identifier)"
        source_archive   = "Internet Archive"
        source_connector = "InternetArchive"
        title            = if ($doc.title)   { $doc.title }   else { $doc.identifier }
        description      = $desc
        date             = $date
        url              = "https://archive.org/details/$($doc.identifier)"
        thumbnail        = "https://archive.org/services/img/$($doc.identifier)"
        format           = $format
        rights           = $rights
        subject          = $subjects
        relevance_score  = 0.65
        extra            = @{
          identifier = $doc.identifier
          creator    = if ($doc.creator)    { $doc.creator }    else { "" }
          publisher  = if ($doc.publisher)  { $doc.publisher }  else { "" }
          mediatype  = $doc.mediatype
        }
      }
    }
    return $results
  }
}
