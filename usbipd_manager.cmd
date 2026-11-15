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

:: Запуск интерактивного интерфейса на PowerShell
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
        $title = "USBIPD MANAGER  •  Управление разрешением проброса USB (bind / unbind)"
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
                $idxStr  = $dev.Index.ToString().PadLeft(2)
                $busStr  = $dev.BusId.PadRight(8)
                $vidStr  = $dev.VidPid.PadRight(9)
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

    function Build-Menu {
        param(
            [array]$Devices,
            [array]$BoundDevices,
            [array]$UnboundDevices
        )

        $items = @()

        if ($Devices.Count -eq 0) {
            $items += [PSCustomObject]@{ Key = "1"; Label = "Обновить состояние"; Action = "REFRESH"; Color = "Yellow" }
            $items += [PSCustomObject]@{ Key = "0"; Label = "Выход"; Action = "EXIT"; Color = "DarkGray" }
            return ,$items
        }

        if ($BoundDevices.Count -eq 0) {
            # Ни одно устройство не забинжено
            $items += [PSCustomObject]@{ Key = "1"; Label = "Разрешить проброс (bind)"; Action = "BIND"; Color = "Cyan" }
            $items += [PSCustomObject]@{ Key = "2"; Label = "Обновить состояние"; Action = "REFRESH"; Color = "Yellow" }
            $items += [PSCustomObject]@{ Key = "0"; Label = "Выход"; Action = "EXIT"; Color = "DarkGray" }
        } elseif ($UnboundDevices.Count -gt 0) {
            # Хотя бы одно устройство забинжено, но не все
            $items += [PSCustomObject]@{ Key = "1"; Label = "Запретить проброс для всех (unbind all)"; Action = "UNBIND_ALL"; Color = "Cyan" }
            $items += [PSCustomObject]@{ Key = "2"; Label = "Запретить проброс (unbind)"; Action = "UNBIND"; Color = "Cyan" }
            $items += [PSCustomObject]@{ Key = "3"; Label = "Разрешить проброс (bind)"; Action = "BIND"; Color = "Cyan" }
            $items += [PSCustomObject]@{ Key = "4"; Label = "Обновить состояние"; Action = "REFRESH"; Color = "Yellow" }
            $items += [PSCustomObject]@{ Key = "0"; Label = "Выход"; Action = "EXIT"; Color = "DarkGray" }
        } else {
            # Все устройства забинжены
            $items += [PSCustomObject]@{ Key = "1"; Label = "Запретить проброс для всех (unbind all)"; Action = "UNBIND_ALL"; Color = "Cyan" }
            $items += [PSCustomObject]@{ Key = "2"; Label = "Запретить проброс (unbind)"; Action = "UNBIND"; Color = "Cyan" }
            $items += [PSCustomObject]@{ Key = "3"; Label = "Обновить состояние"; Action = "REFRESH"; Color = "Yellow" }
            $items += [PSCustomObject]@{ Key = "0"; Label = "Выход"; Action = "EXIT"; Color = "DarkGray" }
        }

        return ,$items
    }

    function Show-Menu {
        param([array]$MenuItems)

        Write-Host "╭──────────────────────────────────────────────────────────────────────────────────────╮" -ForegroundColor DarkGray
        foreach ($item in $MenuItems) {
            $paddedLabel = $item.Label.PadRight(80)
            $textColor = if ($item.Action -eq "EXIT") { "Gray" } else { "White" }

            Write-Host "│  " -ForegroundColor DarkGray -NoNewline
            Write-Host "$($item.Key)." -ForegroundColor $item.Color -NoNewline
            Write-Host " $paddedLabel" -ForegroundColor $textColor -NoNewline
            Write-Host " │" -ForegroundColor DarkGray
        }
        Write-Host "╰──────────────────────────────────────────────────────────────────────────────────────╯" -ForegroundColor DarkGray
        Write-Host ""
    }

    while ($true) {
        $devices        = Get-ConnectedUsbDevices
        $boundDevices   = @($devices | Where-Object { $_.State -ne "Not shared" })
        $unboundDevices = @($devices | Where-Object { $_.State -eq "Not shared" })

        Show-Header
        Show-DevicesTable -Devices $devices

        $menuItems = Build-Menu -Devices $devices -BoundDevices $boundDevices -UnboundDevices $unboundDevices
        Show-Menu -MenuItems $menuItems

        $choice = (Read-Host "Выберите действие").Trim()
        $selected = $menuItems | Where-Object { $_.Key -eq $choice } | Select-Object -First 1

        if (-not $selected) { continue }

        switch ($selected.Action) {
            "BIND" {
                Write-Host ""
                $num = (Read-Host "Введите номер устройства (1-$($devices.Count), 0 — отмена)").Trim()
                if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $devices.Count) {
                    $target = $devices[[int]$num - 1]
                    Write-Host "[*] Выполнение: usbipd bind --busid $($target.BusId) ($($target.Name))..." -ForegroundColor Cyan
                    usbipd bind --busid $target.BusId
                    Start-Sleep -Milliseconds 1200
                }
            }
            "UNBIND" {
                Write-Host ""
                $num = (Read-Host "Введите номер устройства (1-$($devices.Count), 0 — отмена)").Trim()
                if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $devices.Count) {
                    $target = $devices[[int]$num - 1]
                    Write-Host "[*] Выполнение: usbipd unbind --busid $($target.BusId) ($($target.Name))..." -ForegroundColor Yellow
                    usbipd unbind --busid $target.BusId
                    Start-Sleep -Milliseconds 1200
                }
            }
            "UNBIND_ALL" {
                Write-Host ""
                foreach ($t in $boundDevices) {
                    Write-Host "[*] Выполнение: usbipd unbind --busid $($t.BusId) ($($t.Name))..." -ForegroundColor Yellow
                    usbipd unbind --busid $t.BusId
                }
                Start-Sleep -Milliseconds 1200
            }
            "REFRESH" {
                continue
            }
            "EXIT" {
                exit 0
            }
        }
    }
} catch {
    Write-Host "`n[ОШИБКА] $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода"
    exit 1
}
