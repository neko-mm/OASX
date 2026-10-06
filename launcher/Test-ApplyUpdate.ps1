$ErrorActionPreference = 'Stop'
$apply = Join-Path $PSScriptRoot 'OASX.Update.Apply.ps1'
$root = Join-Path $env:TEMP ('oasx-apply-test-' + [guid]::NewGuid().ToString('N'))

function Assert([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function New-Fixture([string]$name) {
    $base = Join-Path $root $name
    $install = Join-Path $base 'install'
    $work = Join-Path $base 'work'
    $stage = Join-Path $work 'stage'
    New-Item -ItemType Directory -Path $install, $stage,
        (Join-Path $install 'config'), (Join-Path $install 'data'),
        (Join-Path $stage 'data') -Force | Out-Null
    Set-Content (Join-Path $install 'oasx.exe') 'old'
    Set-Content (Join-Path $install 'OASX.Launcher.exe') 'old launcher'
    Set-Content (Join-Path $install 'oasx-update-channel.txt') 'test'
    Set-Content (Join-Path $install 'data/asset.txt') 'old data'
    Set-Content (Join-Path $install 'connectivity_plus_plugin.dll') 'old dll'
    Set-Content (Join-Path $install 'config/user.json') 'keep me'
    Set-Content (Join-Path $install 'package-files.txt') @(
        'oasx.exe', 'OASX.Launcher.exe', 'connectivity_plus_plugin.dll',
        'data', 'package-files.txt')
    Set-Content (Join-Path $stage 'oasx.exe') 'new'
    Set-Content (Join-Path $stage 'data/asset.txt') 'new data'
    Set-Content (Join-Path $stage 'connectivity_plus_plugin.dll') 'new dll'
    Set-Content (Join-Path $stage 'OASX.Launcher.exe') 'launcher'
    Set-Content (Join-Path $stage 'OASX.Update.Apply.ps1') 'apply'
    Set-Content (Join-Path $stage 'oasx-channel.txt') 'stable'
    Set-Content (Join-Path $stage 'oasx-release.txt') 'v2026.10.2.1'
    Set-Content (Join-Path $stage 'package-files.txt') @(
        'oasx.exe', 'data', 'connectivity_plus_plugin.dll',
        'OASX.Launcher.exe', 'OASX.Update.Apply.ps1',
        'oasx-channel.txt', 'oasx-release.txt', 'package-files.txt'
    )
    return @{ Install = $install; Work = $work }
}

try {
    $success = New-Fixture 'success'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $apply `
        -InstallDir $success.Install -WorkRoot $success.Work -LauncherPid 0 -TestMode
    Assert ($LASTEXITCODE -eq 0) 'Successful update returned an error.'
    Assert ((Get-Content (Join-Path $success.Install 'oasx.exe') -Raw).Trim() -eq 'new') 'App was not replaced.'
    Assert ((Get-Content (Join-Path $success.Install 'OASX.Launcher.exe') -Raw).Trim() -eq 'launcher') 'Launcher was not replaced.'
    Assert ((Get-Content (Join-Path $success.Install 'oasx-update-channel.txt') -Raw).Trim() -eq 'test') 'Channel preference changed.'
    Assert ((Get-Content (Join-Path $success.Install 'data/asset.txt') -Raw).Trim() -eq 'new data') 'Data was not replaced.'
    Assert ((Get-Content (Join-Path $success.Install 'config/user.json') -Raw).Trim() -eq 'keep me') 'User config changed.'
    Assert (-not (Test-Path $success.Work)) 'Successful update left temporary files.'

    $failure = New-Fixture 'failure'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $apply `
        -InstallDir $failure.Install -WorkRoot $failure.Work -LauncherPid 0 `
        -TestMode -FailAfterCopy
    Assert ($LASTEXITCODE -eq 1) 'Simulated failure returned success.'
    Assert ((Get-Content (Join-Path $failure.Install 'oasx.exe') -Raw).Trim() -eq 'old') 'Rollback did not restore the app.'
    Assert ((Get-Content (Join-Path $failure.Install 'OASX.Launcher.exe') -Raw).Trim() -eq 'old launcher') 'Rollback did not restore the launcher.'
    Assert ((Get-Content (Join-Path $failure.Install 'oasx-update-channel.txt') -Raw).Trim() -eq 'test') 'Rollback changed channel preference.'
    Assert ((Get-Content (Join-Path $failure.Install 'data/asset.txt') -Raw).Trim() -eq 'old data') 'Rollback did not restore data.'
    Assert ((Get-Content (Join-Path $failure.Install 'config/user.json') -Raw).Trim() -eq 'keep me') 'Rollback changed user config.'
    Assert (-not (Test-Path $failure.Work)) 'Rollback left temporary files.'

    $locked = New-Fixture 'locked'
    $lockedDll = Join-Path $locked.Install 'connectivity_plus_plugin.dll'
    $handle = [System.IO.File]::Open($lockedDll,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::None)
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $apply `
            -InstallDir $locked.Install -WorkRoot $locked.Work -LauncherPid 0 -TestMode
        Assert ($LASTEXITCODE -eq 1) 'Locked DLL was not rejected.'
        Assert ((Get-Content (Join-Path $locked.Install 'oasx.exe') -Raw).Trim() -eq 'old') 'Locked update changed the app.'
        Assert ((Get-Content (Join-Path $locked.Install 'OASX.Launcher.exe') -Raw).Trim() -eq 'old launcher') 'Locked update removed the launcher.'
        Assert ((Get-Content (Join-Path $locked.Install 'data/asset.txt') -Raw).Trim() -eq 'old data') 'Locked update changed data.'
        Assert (-not (Test-Path $locked.Work)) 'Locked update left temporary files.'
    }
    finally { $handle.Dispose() }
    Assert ((Get-Content $lockedDll -Raw).Trim() -eq 'old dll') 'Locked update changed the DLL.'
    Write-Host 'ApplyUpdate success, rollback and locked-file tests passed.'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
