param (
    [string] $ClustersCsv,
    [string] $CommandScript,
    [string] $ParamsJson
)

$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

$Clusters = $ClustersCsv | Import-Csv -Delimiter ";"
$Params = @{}
(Get-Content -Raw -Path $ParamsJson | ConvertFrom-Json).psobject.properties | foreach { $Params[$_.Name] = $_.Value }

$Clusters | foreach {
    Write-Host "`r`nEsecuzione '$CommandScript' su $($_.Acronimo) $($_.Ambiente) ($($_.Installazione))`r`n" -BackgroundColor DarkRed
    . $ScriptPath\$CommandScript.ps1 -Acronimo $_.Acronimo -Ambiente $_.Ambiente -InstallationType $_.Installazione @Params
}

if (-not $psise) { Read-Host "`r`nPremere invio per chiudere" }