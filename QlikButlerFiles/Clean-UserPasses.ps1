<#

.SINOSSI

    Rimuovi l'assegnazione degli pass di accesso per gli utenti che sono stati inattivi per alcuni giorni.

.NOTE

    Autori: Matteo Silvestro, Levi Turner
    Versione: 3.0.2
    Ultimo aggiornamento: 25/11/2019
    Basato su: qlik_sense_purge_unused_user_access_passes.ps1 <https://github.com/levi-turner/QlikSenseScripts/blob/master/qlik_sense_purge_unused_user_access_passes.ps1>

#>

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

# Giorni di inattività dopo i quali viene svecchiata la licenza.
$InactivityThreshold = 90 # 3 mesi
$InactiveDate = (Get-Date).AddDays(-$InactivityThreshold).ToString("yyyy/MM/dd")

# Connessione all'ambiente.
try {
    Connect-Qlik -ComputerName $env:COMPUTERNAME -UseDefaultCredentials -TrustAllCerts | Out-Null
} catch {
    Write-Host "Impossibile connettersi a $env:COMPUTERNAME." -BackgroundColor Red
    if (-not $psise) { Read-Host "`r`nPremere invio per chiudere" }
    exit
}

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

# File di log.
$Date = Get-Date -UFormat "%Y_%m_%d__%H_%M_%S"
$BackupRoot = $SystemConfig.BackupRoot
$Log = "$BackupRoot\$ClusterName\Logs\SvecchiamentoLicenze-$Date.log"

# Trascrivi l'output della console in un file di traccia.
Start-Transcript -Path $Log

function Remove-QlikUserAccessType {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $Id,
        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $UserName
    )

    process {
        Write-Output "Rimozione licenza per $UserName..."
        Invoke-QlikDelete -path "/qrs/license/useraccesstype/$Id" | Out-Null
    }
}

$UserPasses = Get-QlikUserAccessType -filter "lastUsed lt '$InactiveDate'" -full
if ($UserPasses) {
    $UserPasses | Select-Object -Property id, @{name = 'username'; expression = { $_.user.name }} | Remove-QlikUserAccessType
} else {
    Write-Output "Nessuna licenza da svecchiare."
}

Stop-Transcript