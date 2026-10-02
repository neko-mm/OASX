param(
    [Parameter(Mandatory = $true)][ValidateSet('test', 'stable')][string]$Channel,
    [Parameter(Mandatory = $true)][string]$Version
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$release = Join-Path $repo 'build/windows/x64/runner/Release'
if (-not (Test-Path -LiteralPath $release)) {
    $release = Join-Path $repo 'build/windows/runner/Release'
}
if (-not (Test-Path -LiteralPath (Join-Path $release 'oasx.exe'))) {
    throw 'Flutter Windows release directory is missing.'
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$msbuild = & $vswhere -latest -requires Microsoft.Component.MSBuild `
    -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild was not found.' }
& $msbuild (Join-Path $PSScriptRoot 'OASX.Launcher.csproj') `
    /p:Configuration=Release /p:Platform=AnyCPU /v:minimal
if ($LASTEXITCODE -ne 0) { throw 'OASX launcher build failed.' }

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin/Release/OASX.Launcher.exe') `
    -Destination (Join-Path $release 'OASX.Launcher.exe') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'OASX.Update.Apply.ps1') `
    -Destination (Join-Path $release 'OASX.Update.Apply.ps1') -Force
[System.IO.File]::WriteAllText((Join-Path $release 'oasx-channel.txt'), $Channel)
[System.IO.File]::WriteAllText((Join-Path $release 'oasx-release.txt'), $Version)

$roots = @(Get-ChildItem -LiteralPath $release | ForEach-Object { $_.Name })
$roots += 'package-files.txt'
$roots = @($roots | Sort-Object -Unique)
[System.IO.File]::WriteAllLines((Join-Path $release 'package-files.txt'), $roots)
Write-Host "Packaged OASX $Channel $Version with $($roots.Count) managed roots."
