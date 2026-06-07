#Requires -Version 7.0
param(
  [Parameter(Mandatory = $true)]
  [string]$AudioFilePath,

  [Parameter(Mandatory = $true)]
  [string]$OpenAIApiKey,

  [int]$MaxRetries = 2,
  [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

function Test-AudioFile {
  param([string]$FilePath)

  if (-not (Test-Path $FilePath)) {
    throw "Audio file not found: $FilePath"
  }

  $file = Get-Item $FilePath
  $maxSizeMB = 100
  $maxSizeBytes = $maxSizeMB * 1024 * 1024

  if ($file.Length -gt $maxSizeBytes) {
    throw "Audio file exceeds $maxSizeMB MB limit: $($file.Length / 1024 / 1024) MB"
  }

  $validExtensions = @(".mp4", ".wav", ".mp3", ".mov", ".m4a", ".flac", ".ogg")
  $ext = $file.Extension.ToLower()

  if ($validExtensions -notcontains $ext) {
    throw "Unsupported audio format: $ext. Supported: $($validExtensions -join ', ')"
  }

  return $file
}

function Invoke-WhisperAPI {
  param(
    [string]$FilePath,
    [string]$ApiKey,
    [int]$Attempt = 1
  )

  $uri = "https://api.openai.com/v1/audio/transcriptions"

  $headers = @{
    "Authorization" = "Bearer $ApiKey"
  }

  try {
    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $fileName = (Get-Item $FilePath).Name

    $form = @{
      file   = @{
        filename = $fileName
        data     = $fileBytes
      }
      model  = "whisper-1"
      language = "en"
    }

    Write-Host "Calling Whisper API (attempt $Attempt)..."

    $response = Invoke-RestMethod `
      -Uri $uri `
      -Headers $headers `
      -Form $form `
      -TimeoutSec $TimeoutSeconds `
      -Method Post

    return $response
  }
  catch {
    if ($Attempt -lt $MaxRetries) {
      $backoff = [Math]::Pow(2, $Attempt - 1) * 2
      Write-Host "Whisper API call failed: $_. Retrying in $backoff seconds..."
      Start-Sleep -Seconds $backoff
      return Invoke-WhisperAPI -FilePath $FilePath -ApiKey $ApiKey -Attempt ($Attempt + 1)
    }
    else {
      throw "Whisper API failed after $MaxRetries attempts: $_"
    }
  }
}

function Main {
  Write-Host "=== Whisper Transcriber ==="

  $audioFile = Test-AudioFile -FilePath $AudioFilePath
  Write-Host "Audio file validated: $($audioFile.Name) ($([Math]::Round($audioFile.Length / 1024 / 1024, 2)) MB)"

  $transcriptionResult = Invoke-WhisperAPI -FilePath $AudioFilePath -ApiKey $OpenAIApiKey

  return @{
    text              = $transcriptionResult.text
    language          = $transcriptionResult.language
    duration_seconds  = [Math]::Round($transcriptionResult.duration, 0)
    model             = $transcriptionResult.model
    success           = $true
  }
}

$result = Main
$result | ConvertTo-Json -Depth 5 | Write-Output
