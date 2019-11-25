param (
    [string] $NodesCsv,
    [string] $CommandScript,
    [string] $ParamsJson
)

$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

$Nodes = $NodesCsv | Import-Csv -Delimiter ";"
$Params = @{}
(Get-Content -Raw -Path $ParamsJson | ConvertFrom-Json).psobject.properties | foreach { $Params[$_.Name] = $_.Value }

$Nodes | foreach {
    Write-Host "`r`nEsecuzione '$CommandScript' su $($_.Hostname)`r`n" -BackgroundColor DarkRed
    . $ScriptPath\$CommandScript.ps1 -Node $_.Hostname @Params
}

if (-not $psise) { Read-Host "`r`nPremere invio per chiudere" }