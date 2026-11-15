<# :
@echo off
chcp 65001 > nul
title Управление устройствами usbipd

net session >nul 2>&1
if %errorlevel% neq 0 (
    set "SCRIPT_PATH=%~f0"
    powershell -NoProfile -Command "if (Get-Command wt -ErrorAction SilentlyContinue) { Start-Process wt -Verb RunAs -ArgumentList @('cmd', '/c', ('\"{0}\"' -f $env:SCRIPT_PATH)) } else { Start-Process -FilePath $env:SCRIPT_PATH -Verb RunAs }"
    exit /b
)

set "SCRIPT_PATH=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$b=[IO.File]::ReadAllBytes($env:SCRIPT_PATH);try{$c=(New-Object Text.UTF8Encoding $false,$true).GetString($b)}catch{$c=[Text.Encoding]::GetEncoding(1251).GetString($b)};Invoke-Expression $c.TrimStart([char]0xFEFF)"
if %errorlevel% neq 0 (
    echo.
    pause
)
exit /b
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Get-Command "usbipd" -ErrorAction SilentlyContinue)) {
    Write-Host "[Ошибка] Утилита usbipd не найдена в PATH." -ForegroundColor Red
    exit 1
}

function Get-UsbipdDevices {
    $raw = cmd /c "chcp 65001 > nul && usbipd list"
    $list = @()
    foreach ($line in $raw) {
        if ($line -match '^\s*(\d+-[\d\.]+)\s+([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\s+(.+?)\s+(Not shared|Shared|Attached.*)$') {
            $list += [PSCustomObject]@{
                BusId  = $matches[1]
                VidPid = $matches[2]
                Name   = $matches[3].Trim()
                State  = $matches[4].Trim()
            }
        }
    }
    return $list
}

function Select-DevicesFromList {
    param(
        [array]$DeviceList,
        [string]$PromptText
    )

    for ($i = 0; $i -lt $DeviceList.Count; $i++) {
        $dev = $DeviceList[$i]
        Write-Host ("  {0}. [{1}] {2} ({3}) - {4}" -f ($i + 1), $dev.BusId, $dev.Name, $dev.VidPid, $dev.State)
    }

    Write-Host ""
    $selection = Read-Host $PromptText

    if ([string]::IsNullOrWhiteSpace($selection)) {
        return @()
    }

    $tokens = $selection -split '[\s,;]+' | Where-Object { $_ -ne '' }
    $selectedIndices = New-Object System.Collections.Generic.HashSet[int]

    foreach ($token in $tokens) {
        if ($token -match '^\d+$') {
            $idx = [int]$token - 1
            if ($idx -ge 0 -and $idx -lt $DeviceList.Count) {
                [void]$selectedIndices.Add($idx)
            }
            else {
                Write-Host "[Предупреждение] Номер '$token' вне диапазона и будет пропущен." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "[Предупреждение] Некорректный ввод '$token' пропущен." -ForegroundColor Yellow
        }
    }

    $result = @()
    foreach ($idx in ($selectedIndices | Sort-Object)) {
        $result += $DeviceList[$idx]
    }
    return $result
}

function Invoke-UnbindDevices {
    param([array]$DevicesToUnbind)

    Write-Host ""
    $successList = @()
    $failedList  = @()

    foreach ($dev in $DevicesToUnbind) {
        Write-Host "Отключение [$($dev.BusId)] $($dev.Name)..." -NoNewline
        $cmdOut = usbipd unbind --busid $dev.BusId 2>&1
        Start-Sleep -Milliseconds 400
        $newState = (Get-UsbipdDevices | Where-Object { $_.BusId -eq $dev.BusId }).State

        if ($newState -eq "Not shared") {
            Write-Host " OK" -ForegroundColor Green
            $successList += $dev
        }
        else {
            Write-Host " ОШИБКА (статус: $newState)" -ForegroundColor Red
            if ($cmdOut) { Write-Host "   Детали: $cmdOut" -ForegroundColor DarkRed }
            $failedList += $dev
        }
    }

    Write-Host "`n--- Итог операции ---" -ForegroundColor Cyan
    if ($successList.Count -gt 0) {
        Write-Host "Отключены устройства:" -ForegroundColor Green
        foreach ($dev in $successList) {
            Write-Host "  * [$($dev.BusId)] $($dev.Name) ($($dev.VidPid))"
        }
    }
    if ($failedList.Count -gt 0) {
        Write-Host "Не удалось отключить:" -ForegroundColor Red
        foreach ($dev in $failedList) {
            Write-Host "  * [$($dev.BusId)] $($dev.Name)"
        }
    }
    Write-Host "----------------------`n" -ForegroundColor Cyan
}

function Invoke-BindDevices {
    param([array]$DevicesToBind)

    Write-Host ""
    $successList = @()
    $failedList  = @()

    foreach ($dev in $DevicesToBind) {
        Write-Host "Подключение [$($dev.BusId)] $($dev.Name)..." -NoNewline
        $cmdOut = usbipd bind --busid $dev.BusId 2>&1
        Start-Sleep -Milliseconds 400
        $newState = (Get-UsbipdDevices | Where-Object { $_.BusId -eq $dev.BusId }).State

        if ($newState -eq "Shared" -or $newState -like "Attached*") {
            Write-Host " OK ($newState)" -ForegroundColor Green
            $successList += [PSCustomObject]@{ Device = $dev; State = $newState }
        }
        else {
            Write-Host " ОШИБКА (статус: $newState)" -ForegroundColor Red
            if ($cmdOut) { Write-Host "   Детали: $cmdOut" -ForegroundColor DarkRed }
            $failedList += $dev
        }
    }

    Write-Host "`n--- Итог операции ---" -ForegroundColor Cyan
    if ($successList.Count -gt 0) {
        Write-Host "Подключены устройства:" -ForegroundColor Green
        foreach ($item in $successList) {
            Write-Host "  * [$($item.Device.BusId)] $($item.Device.Name) ($($item.Device.VidPid)) -> $($item.State)"
        }
    }
    if ($failedList.Count -gt 0) {
        Write-Host "Не удалось подключить:" -ForegroundColor Red
        foreach ($dev in $failedList) {
            Write-Host "  * [$($dev.BusId)] $($dev.Name)"
        }
    }
    Write-Host "----------------------`n" -ForegroundColor Cyan
}

# Основной цикл программы
while ($true) {
    $allDevices = @(Get-UsbipdDevices)

    Write-Host "=== Текущий список USB-устройств ===" -ForegroundColor Cyan
    if ($allDevices.Count -eq 0) {
        Write-Host "  USB-устройства не обнаружены." -ForegroundColor Yellow
    }
    else {
        foreach ($dev in $allDevices) {
            if ($dev.State -ne "Not shared") {
                Write-Host ("  [ПОДКЛЮЧЕНО]    [{0}] {1} ({2}) - {3}" -f $dev.BusId, $dev.Name, $dev.VidPid, $dev.State) -ForegroundColor Green
            }
            else {
                Write-Host ("  [Не подключено] [{0}] {1} ({2})" -f $dev.BusId, $dev.Name, $dev.VidPid) -ForegroundColor Gray
            }
        }
    }

    $activeDevices   = @($allDevices | Where-Object { $_.State -ne "Not shared" })
    $unsharedDevices = @($allDevices | Where-Object { $_.State -eq "Not shared" })

    # Динамическое формирование пунктов меню
    $menuItems = @()
    if ($activeDevices.Count -gt 0) {
        $menuItems += [PSCustomObject]@{ Id = "unbind_all"; Label = "Отключить все устройства ($($activeDevices.Count) шт.)" }
        $menuItems += [PSCustomObject]@{ Id = "unbind";     Label = "Отключить" }
    }
    if ($unsharedDevices.Count -gt 0) {
        $menuItems += [PSCustomObject]@{ Id = "bind";       Label = "Подключить" }
    }
    $menuItems += [PSCustomObject]@{ Id = "exit"; Label = "Выход" }

    Write-Host "`nВыберите действие:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $menuItems.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $menuItems[$i].Label)
    }

    Write-Host ""
    $choiceRaw = (Read-Host "Введите номер действия").Trim()

    if ($choiceRaw -notmatch '^\d+$') {
        Write-Host "[Предупреждение] Введите число от 1 до $($menuItems.Count).`n" -ForegroundColor Yellow
        continue
    }

    $choiceIdx = [int]$choiceRaw - 1
    if ($choiceIdx -lt 0 -or $choiceIdx -ge $menuItems.Count) {
        Write-Host "[Предупреждение] Пункт '$choiceRaw' отсутствует в меню.`n" -ForegroundColor Yellow
        continue
    }

    $selectedAction = $menuItems[$choiceIdx].Id

    switch ($selectedAction) {
        "unbind_all" {
            Invoke-UnbindDevices -DevicesToUnbind $activeDevices
        }

        "unbind" {
            Write-Host "`nПодключенные устройства:" -ForegroundColor Cyan
            $toUnbind = @(Select-DevicesFromList -DeviceList $activeDevices -PromptText "Введите номера для отключения (через пробел или запятую, например: 1 2)")
            if ($toUnbind.Count -eq 0) {
                Write-Host "Ничего не выбрано.`n" -ForegroundColor Yellow
            }
            else {
                Invoke-UnbindDevices -DevicesToUnbind $toUnbind
            }
        }

        "bind" {
            Write-Host "`nДоступные для подключения устройства:" -ForegroundColor Cyan
            $toBind = @(Select-DevicesFromList -DeviceList $unsharedDevices -PromptText "Введите номера для подключения (через пробел или запятую, например: 1 3)")
            if ($toBind.Count -eq 0) {
                Write-Host "Ничего не выбрано.`n" -ForegroundColor Yellow
            }
            else {
                Invoke-BindDevices -DevicesToBind $toBind
            }
        }

        "exit" {
            exit 0
        }
    }
}