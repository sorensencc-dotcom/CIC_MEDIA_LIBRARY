<#
  Ancestry.com API — restricted partner program.
  Apply at: https://www.ancestry.com/corporate/brands/ancestry/genealogy-api
  Auth: OAuth 2.0 (partner credentials required)

  STATUS: SCAFFOLD ONLY — Ancestry API requires partner approval.
  The connector is wired up and ready; add credentials once approved.

  Alternative until approval: use FamilySearch (covers most Ancestry record types)
  or Chronicling America for newspaper content.
#>

$script:ConnectorRegistry += @{
  Name           = "Ancestry"
  DisplayName    = "Ancestry.com (Partner API)"
  Domains        = @("genealogy")
  RequiresAuth   = $true
  CredentialKeys = @("api_key","api_secret")
  RateLimitMs    = 1000
  Invoke         = {
    param([string]$Query, [hashtable]$Filters, [int]$MaxResults, [hashtable]$Credentials)

    if (-not $Credentials -or -not $Credentials.api_key) {
      Write-Log "  [Ancestry] SKIP — partner credentials not configured. Apply at ancestry.com/corporate/brands/ancestry/genealogy-api"
      return @()
    }

    # Auth: Ancestry uses OAuth 2.0 bearer token
    $tokenBody = @{
      grant_type    = "client_credentials"
      client_id     = $Credentials.api_key
      client_secret = $Credentials.api_secret
    }
    try {
      $tokenResp = Invoke-RestMethod -Uri "https://www.ancestry.com/api/oauth/token" `
        -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -TimeoutSec 15
      $token = $tokenResp.access_token
    } catch {
      Write-Log "  [Ancestry] Auth failed: $_"
      return @()
    }

    $headers = @{ Authorization = "Bearer $token"; "X-API-Key" = $Credentials.api_key }
    $params  = @{
      query = $Query
      count = [Math]::Min($MaxResults, 20)
    }
    if ($Filters.surname)    { $params["lastname"]  = $Filters.surname   }
    if ($Filters.givenName)  { $params["firstname"] = $Filters.givenName }
    if ($Filters.date_from)  { $params["yearstart"] = $Filters.date_from }
    if ($Filters.date_to)    { $params["yearend"]   = $Filters.date_to   }

    $uri = "https://api.ancestry.com/v2/search?" + (
      $params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" } | Join-String -Separator "&"
    )

    $resp = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 30 -ErrorAction Stop
    $results = @()

    foreach ($record in $resp.records) {
      $results += @{
        result_id        = "anc_$($record.id -replace '[^a-zA-Z0-9]','_')"
        source_archive   = "Ancestry.com — $($record.collection_name)"
        source_connector = "Ancestry"
        title            = $record.title
        description      = if ($record.summary) { $record.summary } else { "" }
        date             = if ($record.year)     { "$($record.year)" } else { "" }
        url              = $record.record_url
        thumbnail        = if ($record.image_url) { $record.image_url } else { "" }
        format           = if ($record.record_type) { $record.record_type.ToLower() } else { "document" }
        rights           = "Ancestry.com subscriber content — client must have account"
        subject          = @()
        relevance_score  = if ($record.score) { [float]$record.score } else { 0.5 }
      }
    }
    return $results
  }
}
