param(
    [string] $Node,
    [string] $Extra
)

# Ottieni la directory da cui è stato lanciato lo script.
$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

Import-Module $ScriptPath\QlikButlerManagerToolbox.psm1

Write-Host "Nodo:`t`t$Node"
Write-Host "Extra:`t`t$Extra"