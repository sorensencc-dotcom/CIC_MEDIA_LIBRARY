param([string]$ScriptPath = 'C:\CIC_MEDIA_LIBRARY\CIC\scripts')

$LogPath = "C:\CIC_MEDIA_LIBRARY\CIC\logs\scheduled_runs"
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }

$RunLog = "$LogPath\run_$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"

function Write-Log {
  param([string]$Message)
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$ts] $Message" | Tee-Object -FilePath $RunLog -Append
}

Write-Log "========== CIC Weekly Operations Started =========="
Write-Log "Time: $(Get-Date)"

try {
  Write-Log "Running follow-ops..."
  & "$ScriptPath\cic-follow-ops.ps1" -ErrorAction Stop
  Write-Log "✓ Follow-ops completed"
} catch {
  Write-Log "✗ Follow-ops failed: $_"
}

try {
  Write-Log "Running marketing curation..."
  & "$ScriptPath\curate-cic-marketing-assets.ps1" -ErrorAction Stop
  Write-Log "✓ Marketing curation completed"
} catch {
  Write-Log "✗ Marketing curation failed: $_"
}

Write-Log "========== CIC Weekly Operations Completed =========="
Write-Log "Log: $RunLog"
