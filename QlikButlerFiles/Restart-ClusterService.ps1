<#

.SINOSSI

    Script per il riavvio dei servizi di un'installazione Qlik Sense o NPrinting.

.DESCRIZIONE

    Lo script esegue le azioni necessarie per il riavvio di Qlik Sense o NPrinting.
    * Arresta i servizi di tutti i nodi del cluster, prima sui rim e poi sui central.
    * Avvia i servizi di tutti i nodi del cluster, prima sui central e poi sui rim.
    * Controlla la raggiungibilità dell'Hub di Qlik Sense oppure della console web NPrinting.

.NOTE

    Autore: Matteo Silvestro
    Versione: 3.0.0
    Ultimo aggiornamento: 22/11/2019

#>
param (
    [switch] $OnlyStop = $false,
    [switch] $OnlyStart = $false
)

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

# Importa le funzioni ausiliari per l'avvio e l'arresto dei servizi.
Import-Module $InstallPath\QlikButler\Data\QlikButlerToolbox.psm1

# Carica il file di configurazione.
$ClusterConfig = Import-ConfigFile -ConfigFile $InstallPath\QlikButler\Data\Cluster.config

# Elenco variabili che variano in base all'ambiente, estratte dal file di configurazione.
$Ambiente = $ClusterConfig.Ambiente
$Acronimo = $ClusterConfig.Acronimo
$ClusterName = "$($Acronimo)_$Ambiente"
$ClusterCentral = Split-ConfigLine -ConfigLine $ClusterConfig.ClusterCentral
$ClusterRim = Split-ConfigLine -ConfigLine $ClusterConfig.ClusterRim
$ClusterAll = (,$ClusterCentral + $ClusterRim) | Where-Object { $_ } # rimuovi elementi nulli, se ce ne sono (es. no rim)
$InstallationType = $ClusterConfig.Installazione
if ($InstallationType -eq "NPrinting") {
    $ClusterName += "_$InstallationType"
}

# File di log e backup.
$Date = Get-Date -UFormat "%Y_%m_%d__%H_%M_%S"
$RestartLog = "$InstallPath\Logs\$ClusterName-Riavvio-$Date.log"

# Trascrivi l'output della console in un file di traccia.
Start-Transcript -Path $RestartLog

# Arresta tutti i servizi, prima sui rim e poi sui central.
if (-not $OnlyStart) {
    $ClusterRim | Stop-QlikService

    $ClusterCentral | Stop-QlikService
}

# Avvia tutti i servizi, prima sui central e poi sui rim.
if (-not $OnlyStop) {
    $ClusterCentral | Start-QlikService

    $ClusterRim | Start-QlikService
}

if (-not $OnlyStop) {

    # Controlla la raggiungibilità di Qlik Sense o NPrinting.
    Write-Output "`r`nIn attesa avvio $InstallationType per controllo raggiungibilità..."

    $SecondsToWait = 45
    1..$SecondsToWait | ForEach-Object {
        Write-Progress -Activity "In attesa" -Status "Avvio $InstallationType" -PercentComplete ($_/$SecondsToWait * 100)
        Start-Sleep -Seconds 1
    }

    if ($InstallationType -eq "Qlik Sense") {
        foreach ($Node in $ClusterCentral) {
            $TestQlikSense = Test-QlikSenseAccess -ComputerName $Node
            Write-Output "Central $($Node): $(if (-not $TestQlikSense) {"NON "})raggiungibile."
        }
        foreach ($Node in $ClusterRim) {
            $TestQlikSense = Test-QlikSenseAccess -ComputerName $Node
            Write-Output "Rim $($Node): $(if (-not $TestQlikSense) {"NON "})raggiungibile."
        }
    } elseif ($InstallationType -eq "NPrinting") {
        $TestNPrinting = Test-NPrintingAccess -ComputerName (Get-NodeName)
        Write-Output "Console NPrinting: $(if (-not $TestNPrinting) {"NON "})raggiungibile."
    }

}

Stop-Transcript