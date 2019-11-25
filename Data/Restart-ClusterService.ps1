param(
    [string] $Acronimo,
    [string] $Ambiente,
    [string] $InstallationType
)
# Ottieni la directory da cui è stato lanciato lo script.
$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

Import-Module $ScriptPath\QlikButlerManagerToolbox.psm1

$ClusterCentral = Import-Csv $ScriptPath\NodiCluster.csv -Delimiter ';' | where { ($_.Acronimo -eq $Acronimo) -and ($_.Ambiente -eq $Ambiente) -and ($_.Installazione -eq $InstallationType) -and ($_.TipoNodo -eq "Central") }

# Ottieni le credenziali per l'accesso alle macchine.
$QlikAdminCredentials = Get-QlikAdminCredentials

Invoke-Command -ComputerName $ClusterCentral.Hostname -Credential $QlikAdminCredentials -ScriptBlock {
    $InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
    if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }
    . $InstallPath\QlikButler\Restart-ClusterService.ps1
}