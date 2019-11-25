param(
    [string] $Acronimo,
    [string] $Ambiente,
    [string] $InstallationType,
    [string] $Extra
)

# Ottieni la directory da cui è stato lanciato lo script.
$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

Import-Module $ScriptPath\QlikButlerManagerToolbox.psm1

Write-Host "Acronimo:`t`t$Acronimo"
Write-Host "Ambiente:`t`t$Ambiente"
Write-Host "Tipo installazione:`t$InstallationType"
Write-Host "Extra:`t`t`t$Extra"