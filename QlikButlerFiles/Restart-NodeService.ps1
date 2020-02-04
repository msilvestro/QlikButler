<#

.SINOSSI

    Script per il riavvio dei servizi di un nodo Qlik Sense o NPrinting.

.DESCRIZIONE

    Lo script esegue le azioni necessarie per il riavvio di Qlik Sense o NPrinting su un nodo.
    * Arresta i servizi.
    * Avvia i servizi.

.NOTE

    Autore: Matteo Silvestro
    Versione: 2.4.0
    Ultimo aggiornamento: 30/08/2019

#>
param (
    [switch] $OnlyStop = $false,
    [switch] $OnlyStart = $false,
    [string[]] $Services = $null
)

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

# Importa le funzioni ausiliari per l'avvio e l'arresto dei servizi.
Import-Module $InstallPath\QlikButler\Data\QlikButlerToolbox.psm1

# File di log.
$Date = Get-Date -UFormat "%Y_%m_%d__%H_%M_%S"
$RestartLog = "$InstallPath\Logs\$(Get-NodeName)-Riavvio-$Date.log"

# Trascrivi l'output della console in un file di traccia.
Start-Transcript -Path $RestartLog

# Arresta tutti i servizi.
if (-not $OnlyStart) {
    if ($Services) {
        Stop-QlikService -Services $Services
    } else {
        Stop-QlikService
    }
}

# Avvia tutti i servizi.
if (-not $OnlyStop) {
    if ($Services) {
        Start-QlikService -Services $Services
    } else {
        Start-QlikService
    }
}

Stop-Transcript