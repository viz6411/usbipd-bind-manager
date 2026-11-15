@echo off
chcp 65001 >nul
setlocal

:: Получаем путь к папке скрипта без завершающего слеша (исправляет ошибку 0x8007010b в wt.exe)
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: Проверка прав администратора и запуск в Windows Terminal
net session >nul 2>&1
if %errorlevel% neq 0 (
    where wt.exe >nul 2>&1
    if %errorlevel% equ 0 (
        powershell -NoProfile -Command "Start-Process wt.exe -ArgumentList '-d', '\"%SCRIPT_DIR%\"', 'cmd', '/c', '\"\"%~f0\"\"' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c', '\"\"%~f0\"\"' -Verb RunAs"
    )
    exit /b
)

:: Перезапуск в Windows Terminal, если скрипт открыт в обычном conhost
if not defined WT_SESSION (
    where wt.exe >nul 2>&1
    if %errorlevel% equ 0 (
        start "" wt.exe -d "%SCRIPT_DIR%" cmd /c ""%~f0""
        exit /b
    )
)

:: Запуск интерактивного интерфейса на PowerShell (UTF-8 + цвета + рамки)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$raw = Get-Content -LiteralPath '%~f0' -Raw -Encoding UTF8; $parts = [regex]::Split($raw, '(?m)^#__PS_BLOCK__\r?$'); Invoke-Expression $parts[1]"
if %errorlevel% neq 0 pause
exit /b

#__PS_BLOCK__
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8

    function Get-ConnectedUsbDevices {
        $raw = usbipd list 2>$null
        $devices = @()
        $inConnected = $false

        foreach ($line in $raw) {
            if ($line -match '^\s*Connected:') {
                $inConnected = $true
                continue
            }
            if ($line -match '^\s*Persisted:') {
                $inConnected = $false
                continue
            }
            if ($inConnected -and $line -match '^\s*(\d+-\d+(?:\.\d+)*)\s+([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\s+(.+?)\s+(Not shared|Shared|Attached)\s*$') {
                $devices += [PSCustomObject]@{
                    Index  = $devices.Count + 1
                    BusId  = $matches[1]
                    VidPid = $matches[2]
                    Name   = $matches[3].Trim()
                    State  = $matches[4]
                }
            }
        }
        return ,$devices
    }

    function Show-Header {
        Clear-Host
        Write-Host "╭──────────────────────────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkCyan
        Write-Host "│  " -ForegroundColor DarkCyan -NoNewline
        Write-Host "USBIPD MANAGER" -ForegroundColor Cyan -NoNewline
        Write-Host "  •  Управление разрешением проброса USB (bind / unbind)              " -ForegroundColor White -NoNewline
        Write-Host "│" -ForegroundColor DarkCyan
        Write-Host "╰──────────────────────────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkCyan
        Write-Host ""
    }

    function Show-DevicesTable {
        param([array]$Devices)

        Write-Host "╭─────┬──────────┬───────────┬──────────────┬──────────────────────────────────────────╮" -ForegroundColor DarkGray
        Write-Host "│  #  │ BUSID    │ VID:PID   │ СТАТУС       │ УСТРОЙСТВО                               │" -ForegroundColor Gray
        Write-Host "├─────┼──────────┼───────────┼──────────────┼──────────────────────────────────────────┤" -ForegroundColor DarkGray

        if ($Devices.Count -eq 0) {
            Write-Host "│" -ForegroundColor DarkGray -NoNewline
            Write-Host "  Подключенные USB-устройства не найдены                                              " -ForegroundColor Yellow -NoNewline
            Write-Host "│" -ForegroundColor DarkGray
        } else {
            foreach ($dev in $Devices) {
                $idxStr = $dev.Index.ToString().PadLeft(2)
                $busStr = $dev.BusId.PadRight(8)
                $vidStr = $dev.VidPid.PadRight(9)
                $nameStr = if ($dev.Name.Length -gt 40) { $dev.Name.Substring(0, 37) + "..." } else { $dev.Name.PadRight(40) }

                Write-Host "│ " -ForegroundColor DarkGray -NoNewline
                Write-Host "$idxStr  " -ForegroundColor White -NoNewline
                Write-Host "│ " -ForegroundColor DarkGray -NoNewline
                Write-Host "$busStr " -ForegroundColor White -NoNewline
                Write-Host "│ " -ForegroundColor DarkGray -NoNewline
                Write-Host "$vidStr " -ForegroundColor DarkGray -NoNewline
                Write-Host "│ " -ForegroundColor DarkGray -NoNewline

                switch ($dev.State) {
                    "Attached"   { Write-Host "● Attached   " -ForegroundColor Green -NoNewline }
                    "Shared"     { Write-Host "◐ Shared     " -ForegroundColor Cyan -NoNewline }
                    "Not shared" { Write-Host "○ Not shared " -ForegroundColor DarkGray -NoNewline }
                }

                Write-Host "│ " -ForegroundColor DarkGray -NoNewline
                if ($dev.State -eq "Attached") {
                    Write-Host "$nameStr " -ForegroundColor Green -NoNewline
                } elseif ($dev.State -eq "Shared") {
                    Write-Host "$nameStr " -ForegroundColor Cyan -NoNewline
                } else {
                    Write-Host "$nameStr " -ForegroundColor White -NoNewline
                }
                Write-Host "│" -ForegroundColor DarkGray
            }
        }

        Write-Host "╰─────┴──────────┴───────────┴──────────────┴──────────────────────────────────────────╯" -ForegroundColor DarkGray
        Write-Host ""
    }

    function Show-Menu {
        Write-Host "╭──────────────────────────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkGray
        Write-Host "│  " -ForegroundColor DarkGray -NoNewline
        Write-Host "[1]" -ForegroundColor Cyan -NoNewline
        Write-Host " Разрешить проброс устройства (bind)                                               " -ForegroundColor White -NoNewline
        Write-Host "│" -ForegroundColor DarkGray

        Write-Host "│  " -ForegroundColor DarkGray -NoNewline
        Write-Host "[2]" -ForegroundColor Cyan -NoNewline
        Write-Host " Запретить проброс устройства (unbind)                                             " -ForegroundColor White -NoNewline
        Write-Host "│" -ForegroundColor DarkGray

        Write-Host "│  " -ForegroundColor DarkGray -NoNewline
        Write-Host "[3]" -ForegroundColor Yellow -NoNewline
        Write-Host " Обновить состояние                                                                " -ForegroundColor White -NoNewline
        Write-Host "│" -ForegroundColor DarkGray

        Write-Host "│  " -ForegroundColor DarkGray -NoNewline
        Write-Host "[0]" -ForegroundColor DarkGray -NoNewline
        Write-Host " Выход                                                                             " -ForegroundColor Gray -NoNewline
        Write-Host "│" -ForegroundColor DarkGray
        Write-Host "╰──────────────────────────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkGray
        Write-Host ""
    }

    while ($true) {
        $devices = Get-ConnectedUsbDevices
        Show-Header
        Show-DevicesTable -Devices $devices
        Show-Menu

        $action = Read-Host "Выберите действие"

        switch ($action.Trim()) {
            "1" {
                if ($devices.Count -eq 0) { continue }
                Write-Host ""
                Write-Host "Введите номер устройства (1-$($devices.Count)), " -NoNewline
                Write-Host "[A]" -ForegroundColor Cyan -NoNewline
                Write-Host " — разрешить все свободные, " -NoNewline
                Write-Host "[0]" -ForegroundColor DarkGray -NoNewline
                Write-Host " — назад"
                $choice = (Read-Host "Выбор").Trim()

                if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { continue }

                if ($choice -ieq "A") {
                    $targets = $devices | Where-Object { $_.State -eq "Not shared" }
                    if (-not $targets) {
                        Write-Host "[!] Нет свободных устройств для разрешения проброса." -ForegroundColor Yellow
                    } else {
                        foreach ($t in $targets) {
                            Write-Host "[*] Разрешение проброса $($t.BusId) ($($t.Name))..." -ForegroundColor Cyan
                            usbipd bind --busid $t.BusId
                        }
                    }
                    Start-Sleep -Milliseconds 1300
                } elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $devices.Count) {
                    $target = $devices[[int]$choice - 1]
                    Write-Host "[*] Разрешение проброса $($target.BusId) ($($target.Name))..." -ForegroundColor Cyan
                    usbipd bind --busid $target.BusId
                    Start-Sleep -Milliseconds 1300
                }
            }
            "2" {
                if ($devices.Count -eq 0) { continue }
                Write-Host ""
                Write-Host "Введите номер устройства (1-$($devices.Count)), " -NoNewline
                Write-Host "[A]" -ForegroundColor Cyan -NoNewline
                Write-Host " — запретить все активные, " -NoNewline
                Write-Host "[0]" -ForegroundColor DarkGray -NoNewline
                Write-Host " — назад"
                $choice = (Read-Host "Выбор").Trim()

                if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { continue }

                if ($choice -ieq "A") {
                    $targets = $devices | Where-Object { $_.State -ne "Not shared" }
                    if (-not $targets) {
                        Write-Host "[!] Нет устройств с активным разрешением проброса." -ForegroundColor Yellow
                    } else {
                        foreach ($t in $targets) {
                            Write-Host "[*] Запрет проброса $($t.BusId) ($($t.Name))..." -ForegroundColor Yellow
                            usbipd unbind --busid $t.BusId
                        }
                    }
                    Start-Sleep -Milliseconds 1300
                } elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $devices.Count) {
                    $target = $devices[[int]$choice - 1]
                    Write-Host "[*] Запрет проброса $($target.BusId) ($($target.Name))..." -ForegroundColor Yellow
                    usbipd unbind --busid $target.BusId
                    Start-Sleep -Milliseconds 1300
                }
            }
            "3" {
                continue
            }
            "0" {
                exit 0
            }
        }
    }
} catch {
    Write-Host "`n[ОШИБКА] $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода"
    exit 1
}
