param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [Parameter(Mandatory = $true)][string]$WorkRoot,
    [Parameter(Mandatory = $true)][int]$LauncherPid,
    [switch]$TestMode,
    [switch]$FailAfterCopy
)

$ErrorActionPreference = 'Stop'
$stage = Join-Path $WorkRoot 'stage'
$backup = Join-Path $WorkRoot 'backup'
$app = Join-Path $InstallDir 'oasx.exe'
$launcher = Join-Path $InstallDir 'OASX.Launcher.exe'
$installed = @()
$saved = @()
$roots = @()
$traceFile = Join-Path $InstallDir 'oasx-update.log'

function Trace([string]$message) {
    try {
        Add-Content -LiteralPath $traceFile -Encoding UTF8 -Value `
            ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' | ' + $message)
    }
    catch { }
}

function Read-ManagedRoots([string]$manifest) {
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return @() }
    $names = @(Get-Content -LiteralPath $manifest -Encoding UTF8 |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    foreach ($name in $names) {
        if ($name -eq '.' -or $name -eq '..' -or
            $name -match '[\\/:]' -or $name.Contains('..')) {
            throw "Invalid managed package path: $name"
        }
    }
    return $names
}

function Remove-Managed([string]$path) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

function Assert-Unlocked([string[]]$names) {
    foreach ($name in $names) {
        $path = Join-Path $InstallDir $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $files = if (Test-Path -LiteralPath $path -PathType Container) {
            @(Get-ChildItem -LiteralPath $path -File -Recurse | ForEach-Object { $_.FullName })
        }
        else { @($path) }
        foreach ($file in $files) {
            try {
                $stream = [System.IO.File]::Open($file,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::None)
                $stream.Dispose()
            }
            catch {
                throw "程序文件仍被占用，请关闭 OASX 后重试：$file"
            }
        }
    }
}

function Show-Failure([string]$message) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        'OASX 更新失败',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

try {
    Trace '替换脚本开始执行'
    if ($LauncherPid -gt 0) {
        $exited = $false
        for ($i = 0; $i -lt 60; $i++) {
            if (-not (Get-Process -Id $LauncherPid -ErrorAction SilentlyContinue)) {
                $exited = $true
                break
            }
            Start-Sleep -Milliseconds 500
        }
        if (-not $exited) { throw 'Timed out waiting for launcher to exit.' }
    }
    Trace '启动器已退出'

    $newRoots = @(Read-ManagedRoots (Join-Path $stage 'package-files.txt'))
    if ($newRoots.Count -eq 0) { throw 'The update package has no managed file list.' }
    $oldRoots = @(Read-ManagedRoots (Join-Path $InstallDir 'package-files.txt'))
    $roots = @($newRoots + $oldRoots | Select-Object -Unique)
    foreach ($required in @('oasx.exe', 'OASX.Launcher.exe', 'oasx-channel.txt',
            'oasx-release.txt', 'package-files.txt', 'OASX.Update.Apply.ps1')) {
        if ($newRoots -notcontains $required -or
            -not (Test-Path -LiteralPath (Join-Path $stage $required))) {
            throw "The package is missing $required"
        }
    }

    $unlocked = $false
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            Assert-Unlocked $roots
            $unlocked = $true
            break
        }
        catch {
            if ($attempt -eq 9) { throw }
            Start-Sleep -Milliseconds 300
        }
    }
    if (-not $unlocked) { throw '程序文件仍被占用。' }

    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($name in $roots) {
        $target = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $target) {
            Move-Item -LiteralPath $target -Destination (Join-Path $backup $name)
            $saved += $name
        }
    }
    Trace '旧文件已备份'

    foreach ($name in $newRoots) {
        $installed += $name
        Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $InstallDir $name) -Recurse -Force
    }
    Trace '新文件已复制'

    if (-not (Test-Path -LiteralPath $app) -or
        -not (Test-Path -LiteralPath $launcher)) {
        throw 'Updated OASX package is incomplete.'
    }
    if ($FailAfterCopy) { throw 'Simulated failure after copying the new package.' }
    if (-not $TestMode) {
        $process = Start-Process -FilePath $launcher `
            -WorkingDirectory $InstallDir -PassThru
        Trace "新版启动器已启动，进程 $($process.Id)"
    }

    # The new process is running; downloaded ZIP, extraction and backup are no
    # longer needed. The apply script was copied into WorkRoot before handoff.
    Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}
catch {
    $failure = $_.Exception.Message
    Trace "替换失败：$failure"
    if ($saved.Count -eq 0 -and $installed.Count -eq 0) {
        Trace '安装未开始，旧版本未改动'
        Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
        if ($TestMode) { Write-Host "Update not applied: $failure" }
        else { Show-Failure "更新未完成，原有程序未改动。`n$failure" }
        exit 1
    }

    $rollbackErrors = @()
    foreach ($name in $installed) {
        try {
            Remove-Managed (Join-Path $InstallDir $name)
        }
        catch { $rollbackErrors += "移除 $name 失败：$($_.Exception.Message)" }
    }
    foreach ($name in $saved) {
        try {
            $target = Join-Path $InstallDir $name
            Remove-Managed $target
            Move-Item -LiteralPath (Join-Path $backup $name) -Destination $target
        }
        catch { $rollbackErrors += "恢复 $name 失败：$($_.Exception.Message)" }
    }

    if ($rollbackErrors.Count -eq 0) {
        Trace '旧版本已恢复'
        if (-not $TestMode -and (Test-Path -LiteralPath $app)) {
            Start-Process -FilePath (Join-Path $InstallDir 'OASX.Launcher.exe') `
                -WorkingDirectory $InstallDir | Out-Null
        }
        Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
        if ($TestMode) { Write-Host "Rolled back: $failure" }
        else { Show-Failure "更新失败，已恢复并启动旧版本。`n$failure" }
    }
    else {
        Trace '恢复旧版本失败'
        $failure += "`n恢复旧版本也失败：$($rollbackErrors -join '; ')"
        if ($TestMode) { Write-Host "Rollback failed: $failure" }
        else { Show-Failure "更新失败，无法自动恢复。备份保留在：`n$backup`n$failure" }
    }
    exit 1
}
