param(
  [string]$FactorioExe = "E:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe",
  [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$TestRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) ".factorio-validation")
)

$ErrorActionPreference = "Stop"

$modsRoot = Join-Path $TestRoot "mods"
$configRoot = Join-Path $TestRoot "config"
$configPath = Join-Path $TestRoot "config\config.ini"
$savesRoot = Join-Path $TestRoot "saves"
$scriptOutputPath = Join-Path $TestRoot "script-output\biter-aware-bot-pathing\validation-test-map.json"
$savePath = Join-Path $savesRoot "babp-validation.zip"
$lockPath = Join-Path $TestRoot ".lock"
$modTargetRoot = Join-Path $modsRoot "biterAwareBotPathing"
$harnessTargetRoot = Join-Path $modsRoot "babpValidationHarness"
$harnessSourceRoot = Join-Path $WorkspaceRoot "tools\validation\babpValidationHarness"
$excludedRootEntries = @(".factorio-test", ".factorio-validation", ".git", ".vscode")

function Reset-Directory([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }

  New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Copy-ModWorkspace([string]$SourceRoot, [string]$DestinationRoot) {
  Reset-Directory -Path $DestinationRoot

  Get-ChildItem -LiteralPath $SourceRoot -Force | Where-Object {
    $excludedRootEntries -notcontains $_.Name
  } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DestinationRoot $_.Name) -Recurse -Force
  }
}

function Copy-Harness([string]$SourceRoot, [string]$DestinationRoot) {
  Reset-Directory -Path $DestinationRoot

  Get-ChildItem -LiteralPath $SourceRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DestinationRoot $_.Name) -Recurse -Force
  }
}

function Invoke-Factorio([string[]]$Arguments, [string]$FailureMessage) {
  $process = Start-Process -FilePath $FactorioExe -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "$FailureMessage (exit code $($process.ExitCode))"
  }
}

New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null
New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
New-Item -ItemType Directory -Path $savesRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $scriptOutputPath) -Force | Out-Null

$normalizedWriteData = $TestRoot.Replace("\", "/")
@"
; version=13
[path]
read-data=__PATH__system-read-data__
write-data=$normalizedWriteData

[general]
locale=en
"@ | Set-Content -LiteralPath $configPath -Encoding ASCII

Copy-ModWorkspace -SourceRoot $WorkspaceRoot -DestinationRoot $modTargetRoot
Copy-Harness -SourceRoot $harnessSourceRoot -DestinationRoot $harnessTargetRoot

@'
{
  "mods":
  [
    {
      "name": "base",
      "enabled": true
    },
    {
      "name": "elevated-rails",
      "enabled": true
    },
    {
      "name": "quality",
      "enabled": true
    },
    {
      "name": "space-age",
      "enabled": true
    },
    {
      "name": "babpValidationHarness",
      "enabled": true
    },
    {
      "name": "biterAwareBotPathing",
      "enabled": true
    }
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $modsRoot "mod-list.json") -Encoding ASCII

if (Test-Path -LiteralPath $scriptOutputPath) {
  Remove-Item -LiteralPath $scriptOutputPath -Force
}

if (Test-Path -LiteralPath $savePath) {
  Remove-Item -LiteralPath $savePath -Force
}

if (Test-Path -LiteralPath $lockPath) {
  Remove-Item -LiteralPath $lockPath -Force
}

Invoke-Factorio -Arguments @(
  "--config", $configPath,
  "--mod-directory", $modsRoot,
  "--disable-audio",
  "--create", $savePath
) -FailureMessage "Factorio save creation failed"

Invoke-Factorio -Arguments @(
  "--config", $configPath,
  "--mod-directory", $modsRoot,
  "--disable-audio",
  "--benchmark", $savePath,
  "--benchmark-ticks", "5",
  "--benchmark-runs", "1",
  "--benchmark-sanitize"
) -FailureMessage "Factorio benchmark validation failed"

if (-not (Test-Path -LiteralPath $scriptOutputPath)) {
  throw "Validation output was not written to $scriptOutputPath"
}

Get-Content -LiteralPath $scriptOutputPath
