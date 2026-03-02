[CmdletBinding()]
param(
  # One or more UI strings you see in VS Code (English). Supports wildcards when -UseWildcard is set.
  [Parameter(Mandatory = $false, Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$Text = @(),

  # Read one query per line from a file (UTF-8).
  [Parameter(Mandatory = $false)]
  [string]$TextFile = "",

  # When set, uses PowerShell -like wildcard matching (e.g. "Thinking*", "*Codex*").
  [Parameter(Mandatory = $false)]
  [switch]$UseWildcard,

  # Strip '&' mnemonics and normalize "..." -> "…" before matching.
  [Parameter(Mandatory = $false)]
  [switch]$Normalize,

  # Emit patch template lines you can paste into apply-copilot-core-patches.ps1.
  [Parameter(Mandatory = $false)]
  [switch]$AsPatchTemplate,

  # Max rows per query.
  [Parameter(Mandatory = $false)]
  [int]$MaxResults = 30
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

function ConvertTo-NlsNormalizedMessage([string]$s) {
  if ($null -eq $s) { return $null }
  $s = $s -replace '&', ''
  $s = $s -replace '\.\.\.', '…'
  return $s
}

if (-not [string]::IsNullOrWhiteSpace($TextFile)) {
  if (-not (Test-Path $TextFile)) {
    throw "找不到 TextFile：$TextFile"
  }
  $fileLines = Get-Content -Path $TextFile -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $Text = @($Text + $fileLines)
}

$Text = @($Text | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($Text.Count -eq 0) {
  throw '请提供要查询的文本：例如 .\scripts\find-core-nls-keys.ps1 "Working..." "Thinking..."'
}

$appRoot = Get-VSCodeAppRoot
$keysPath = Join-Path $appRoot 'out\nls.keys.json'
$msgsPath = Join-Path $appRoot 'out\nls.messages.json'

$keys = Get-Content -Raw -Encoding UTF8 $keysPath | ConvertFrom-Json
$msgs = Get-Content -Raw -Encoding UTF8 $msgsPath | ConvertFrom-Json

# Build a flat index: i -> module/key/msg
$index = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($entry in $keys) {
  $module = $entry[0]
  foreach ($k in $entry[1]) {
    $msg = $msgs[$i]
    $norm = if ($Normalize) { ConvertTo-NlsNormalizedMessage $msg } else { $msg }
    $index.Add([pscustomobject]@{ module = $module; key = $k; raw = $msg; text = $norm })
    $i++
  }
}

foreach ($qRaw in $Text) {
  $q = if ($Normalize) { ConvertTo-NlsNormalizedMessage $qRaw } else { $qRaw }

  Write-Host "=== QUERY: $qRaw ==="

  $hits = if ($UseWildcard) {
    $index | Where-Object { $_.text -like $q }
  } else {
    $index | Where-Object { $_.text -eq $q }
  }

  if (-not $hits) {
    Write-Host '  (no match)'
    continue
  }

  $hits = @($hits | Select-Object -First $MaxResults)
  foreach ($h in $hits) {
    if ($AsPatchTemplate) {
      # Value left blank so you can fill translation.
      "@{ module='$($h.module)'; key='$($h.key)'; value='' }, # raw=$($h.raw)"
    } else {
      "  $($h.module)::$($h.key)  raw=[$($h.raw)]"
    }
  }

  if ($hits.Count -ge $MaxResults) {
    Write-Host "  (truncated to MaxResults=$MaxResults)"
  }
}
