<#
  FamilySearch API — free developer access with OAuth 2.0.
  Registration: https://www.familysearch.org/developers/
  Auth: OAuth 2.0 client credentials (no user login required for record search)
  Endpoint: https://api.familysearch.org/platform/records/search

  Setup:
    1. Register at https://www.familysearch.org/developers/
    2. Create an App to get Client ID
    3. Add credentials to archive_credentials.json:
       { "FamilySearch": { "client_id": "...", "client_secret": "..." } }

  Primary genealogy connector. Covers: Vital records, Census, Immigration, Military.
#>

$script:ConnectorRegistry += @{
  Name           = "FamilySearch"
  DisplayName    = "FamilySearch (LDS Church Archives)"
  Domains        = @("genealogy")
  RequiresAuth   = $true
  CredentialKeys = @("client_id","client_secret")
  RateLimitMs    = 500
  Invoke         = {
    param([string]$Query, [hashtable]$Filters, [int]$MaxResults, [hashtable]$Credentials)

    if (-not $Credentials -or -not $Credentials.client_id) {
      Write-Log "  [FamilySearch] SKIP — credentials not configured (see archive_credentials.json)"
      return @()
    }

    # Step 1: obtain access token
    $tokenBody = @{
      grant_type    = "client_credentials"
      client_id     = $Credentials.client_id
      client_secret = $Credentials.client_secret
    }
    try {
      $tokenResp = Invoke-RestMethod -Uri "https://ident.familysearch.org/cis-web/oauth2/v3/token" `
        -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -TimeoutSec 15
      $accessToken = $tokenResp.access_token
    } catch {
      Write-Log "  [FamilySearch] Auth failed: $_"
      return @()
    }

    # Step 2: build search query using FamilySearch GedcomX search syntax
    $searchParts = @("q.anyText:$Query")
    if ($Filters.surname)    { $searchParts += "q.surname:$($Filters.surname)" }
    if ($Filters.givenName)  { $searchParts += "q.givenName:$($Filters.givenName)" }
    if ($Filters.birthPlace) { $searchParts += "q.birthPlace:$($Filters.birthPlace)" }
    if ($Filters.date_from)  { $searchParts += "q.birthDate:+$($Filters.date_from)" }

    $searchQuery = $searchParts -join " "
    $headers = @{ Authorization = "Bearer $accessToken"; Accept = "application/x-fs-v1+json" }

    $uri = "https://api.familysearch.org/platform/records/search?" + (
      @{
        q     = $searchQuery
        count = [Math]::Min($MaxResults, 20)
        start = 0
      }.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" } | Join-String -Separator "&"
    )

    $resp = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 30 -ErrorAction Stop
    $results = @()

    foreach ($entry in $resp.entries) {
      $content = $entry.content.gedcomx

      $person = $content.persons | Select-Object -First 1
      $name   = if ($person.names)  { ($person.names[0].nameForms[0].fullText) } else { $Query }
      $facts  = if ($person.facts)  { $person.facts } else { @() }

      $birthFact = $facts | Where-Object { $_.type -match "Birth" } | Select-Object -First 1
      $date      = if ($birthFact.date.normalized) { $birthFact.date.normalized[0].value } else { "" }
      $place     = if ($birthFact.place.normalized) { $birthFact.place.normalized[0].value } else { "" }

      $recType = "vital_record"
      if ($entry.title -match "Census")       { $recType = "census" }
      elseif ($entry.title -match "Military")  { $recType = "military_record" }
      elseif ($entry.title -match "Death")     { $recType = "death_certificate" }
      elseif ($entry.title -match "Birth")     { $recType = "birth_certificate" }
      elseif ($entry.title -match "Marriage")  { $recType = "marriage_record" }
      elseif ($entry.title -match "Immigrat")  { $recType = "immigration_record" }

      $recordUrl = ""
      if ($entry.links.record.href) { $recordUrl = $entry.links.record.href }

      $results += @{
        result_id        = "fs_$($entry.id -replace '[^a-zA-Z0-9]','_')"
        source_archive   = "FamilySearch"
        source_connector = "FamilySearch"
        title            = if ($entry.title) { $entry.title } else { $name }
        description      = if ($place) { "Birth place: $place" } else { "" }
        date             = $date
        url              = $recordUrl
        thumbnail        = ""
        format           = $recType
        rights           = "See FamilySearch terms of service"
        subject          = @()
        relevance_score  = if ($entry.score) { [float]$entry.score } else { 0.6 }
      }
    }
    return $results
  }
}
