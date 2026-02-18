[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string[]]$Text,

  [Parameter(Mandatory = $false)]
  [switch]$Contains,

  [Parameter(Mandatory = $false)]
  [int]$MaxResults = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-VSCodeAppRoot {
  $cmd = Get-Command code.cmd -ErrorAction SilentlyContinue
  if ($null -eq $cmd) { $cmd = Get-Command code -ErrorAction SilentlyContinue }
  if ($null -eq $cmd) {
    throw '未找到 code 或 code.cmd，请确认 VS Code 已安装且可在 PATH 中找到。'
  }

  $codePath = $cmd.Source
  $binDir = Split-Path -Parent $codePath
  $installRoot = Resolve-Path (Join-Path $binDir '..')

  $hashDir = Get-ChildItem -Directory $installRoot | Where-Object { $_.Name -match '^[0-9a-f]{8,}$' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $hashDir) {
    throw "无法在 $installRoot 下找到版本目录（形如 hash 的文件夹）。"
  }

  $appRoot = Join-Path $hashDir.FullName 'resources\app'
  if (-not (Test-Path $appRoot)) {
    throw "找不到 VS Code appRoot：$appRoot"
  }

  return $appRoot
}

$appRoot = Get-VSCodeAppRoot
$keysPath = Join-Path $appRoot 'out\nls.keys.json'
$msgsPath = Join-Path $appRoot 'out\nls.messages.json'

if (-not (Test-Path $keysPath)) { throw "找不到：$keysPath" }
if (-not (Test-Path $msgsPath)) { throw "找不到：$msgsPath" }

$keys = Get-Content -Raw -Encoding UTF8 $keysPath | ConvertFrom-Json
$msgs = Get-Content -Raw -Encoding UTF8 $msgsPath | ConvertFrom-Json

$needles = @()
foreach ($t in $Text) {
  if (-not [string]::IsNullOrWhiteSpace($t)) {
    $needles += $t
  }
}

if ($needles.Count -eq 0) {
  throw '没有提供要反查的文本。'
}

$results = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($entry in $keys) {
  $module = $entry[0]
  foreach ($k in $entry[1]) {
    $m = $msgs[$i]
    foreach ($needle in $needles) {
      $match = if ($Contains) { $m -like "*$needle*" } else { $m -eq $needle }
      if ($match) {
        $results.Add([pscustomobject]@{
            module  = $module
            key     = $k
            message = $m
            index   = $i
          })
        if ($results.Count -ge $MaxResults) {
          $results
          return
        }
        break
      }
    }
    $i++
  }
}

$results
