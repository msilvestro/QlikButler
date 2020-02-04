<#

.SINOSSI

    Script per lo svecchiamento dei backup.

.DESCRIZIONE

    Lo script cancella file di backup e log più vecchi di una settimana per il cluster corrente.

.NOTE

    Autore: Matteo Silvestro
    Versione: 3.0.2
    Ultimo aggiornamento: 25/11/2019

#>

### Preparazione variabili necessarie per lo script ###

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

# Importa le funzioni ausiliari per l'avvio e l'arresto dei servizi.
Import-Module $InstallPath\QlikButler\Data\QlikButlerToolbox.psm1

# Carica i file di configurazione.
$ClusterConfig = Import-ConfigFile -ConfigFile $InstallPath\QlikButler\Data\Cluster.config
$SystemConfig = Import-ConfigFile -ConfigFile $InstallPath\QlikButler\Data\System.config

# Elenco variabili che variano in base all'ambiente, estratte dal file di configurazione.
$Ambiente = $ClusterConfig.Ambiente
$Acronimo = $ClusterConfig.Acronimo
$ClusterName = "$($Acronimo)_$($Ambiente)"
$InstallationType = $ClusterConfig.Installazione
if ($InstallationType -eq "NPrinting") {
    $ClusterName += "_$InstallationType"
}
if ($ClusterConfig.GiorniSvecchiamento) {
    $DaysToKeep = $ClusterConfig.GiorniSvecchiamento
} else {
    $DaysToKeep = 2
}
$LogsDaysToKeep = 7 # la ritenzione per i log è meglio sia maggiore

# File di log e backup.
$Date = Get-Date -UFormat "%Y_%m_%d__%H_%M_%S"
$BackupRoot = $SystemConfig.BackupRoot
$BackupPath = "$BackupRoot\$ClusterName"
if (-not (Test-Path $BackupPath)) { New-Item -Path $BackupPath -ItemType Directory | Out-Null }
$LogPath = "$SharedFolder\$ClusterName\Logs"

## Cancella i file di backup e di log più vecchi ##

$TarFiles = (Get-ChildItem -Path $BackupPath\*.tar | Sort-Object -Property Name | Select -Last $DaysToKeep).Name
$DumpFiles = (Get-ChildItem -Path $BackupPath\*.dump | Sort-Object -Property Name | Select -Last $DaysToKeep).Name
$BackupLogs = (Get-ChildItem -Path $BackupPath\Logs\*-Backup_*.log | Sort-Object -Property Name | Select -Last $LogsDaysToKeep).Name
$BackupToolLogs = (Get-ChildItem -Path $BackupPath\Logs\*-BackupTool_*.log | Sort-Object -Property Name | Select -Last $LogsDaysToKeep).Name
$CleanLogs = (Get-ChildItem -Path $BackupPath\Logs\SvecchiamentoBackup_*.log | Sort-Object -Property Name | Select -Last $LogsDaysToKeep).Name

# Trascrivi l'output della console in un file di traccia.
Start-Transcript -Path $LogPath\SvecchiamentoBackup_$Date.log

$StartingSize = (Get-ChildItem -Path $BackupPath -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB
Write-Output ("Peso della cartella $($BackupPath): {0:N2} GB" -f $StartingSize)

Write-Output "`r`n# Rimozione file di backup"
Get-ChildItem -Path $BackupPath\*.tar -Exclude $TarFiles | ForEach-Object {
    Write-Output "Rimozione di $($_.FullName)"
    Remove-Item $_
}
Get-ChildItem -Path $BackupPath\*.dump -Exclude $DumpFiles | ForEach-Object {
    Write-Output "Rimozione di $($_.FullName)"
    Remove-Item $_
}

Write-Output "`r`n# Rimozione file di log"
Get-ChildItem -Path $BackupPath\Logs\*-Backup_*.log -Exclude $BackupLogs | ForEach-Object {
    Write-Output "Rimozione di $($_.FullName)"
    Remove-Item $_
}
Get-ChildItem -Path $BackupPath\Logs\*-BackupTool_*.log -Exclude $BackupToolLogs | ForEach-Object {
    Write-Output "Rimozione di $($_.FullName)"
    Remove-Item $_
}
Get-ChildItem -Path $BackupPath\Logs\SvecchiamentoBackup_*.log -Exclude $CleanLogs | ForEach-Object {
    Write-Output "Rimozione di $($_.FullName)"
    Remove-Item $_
}
# Questo serve per rimuovere i vecchi file di svecchiamento, che venivano chiamati in modo diverso.
Get-ChildItem -Path $BackupPath\Logs\Svecchiamento_*.log | ForEach-Object {
    Write-Output "Rimozione di $($_.FullName)"
    Remove-Item $_
}

$FinalSize = (Get-ChildItem -Path $BackupPath -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB
Write-Output ("`r`nPeso della cartella $($BackupPath): {0:N2} GB" -f $FinalSize)
Write-Output ("Spazio liberato: {0:N2} GB" -f ($StartingSize - $FinalSize))

Stop-Transcript