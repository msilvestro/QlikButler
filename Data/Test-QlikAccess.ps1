<#

.SINOSSI

    Restituisci un resoconto dettagliato dello stato di un nodo.

.SINTASSI

    Test-QlikAccess [-Acronimo] <string> [-Ambiente] <string>  [-InstallationType] <string>

.DESCRIZIONE

    Se il cluster è Qlik Sense, per ogni suo nodo:
    * Esegui un pin al server.
    * Esegui una richiesta HTTP per controllare il funzionamento dell'Engine.
    * Controlla la raggiungibilità della QMC.
    * Controlla la raggiungibilità dell'hub.
    Se il cluster è NPrinting il funzionamento è da rivedere (TODO).

.NOTE

    Autore: Matteo Silvestro
    Versione: 3.0.2
    Ultimo aggiornamento: 11/10/2019

#>

param(
    [string] $Acronimo,
    [string] $Ambiente,
    [string] $InstallationType
)

# Ottieni la directory da cui è stato lanciato lo script.
$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

Import-Module $ScriptPath\QlikButlerManagerToolbox.psm1

$ClusterNodes = Import-Csv $ScriptPath\NodiCluster.csv -Delimiter ';' | where { ($_.Acronimo -eq $Acronimo) -and ($_.Ambiente -eq $Ambiente) -and ($_.Installazione -eq $InstallationType) }

$ClusterNodes | foreach {
    Write-Host "Nodo $($_.Hostname)" -BackgroundColor DarkCyan
    $PingTest = Test-NetConnection -ComputerName $_.Hostname
    Write-Host "Ping:`t`t`t`t" -NoNewline
    if ($PingTest) {
        Write-Host "Successo" -ForegroundColor Green
    } else {
        Write-Host "Errore" -ForegroundColor Red
    }
    if ($InstallationType -eq "Qlik Sense") {
        $HealthCheck = Test-WebPage -Url "https://$($_.Hostname)/engine/healthcheck/"
        $QMCTest = Test-WebPage -Url "https://$($_.Hostname)/qmc"
        $HubTest = Test-WebPage -Url "https://$($_.Hostname)/hub"
        Write-Host "Engine check:`t`t" -NoNewline
        if ($HealthCheck) {
            Write-Host "Successo" -ForegroundColor Green
        } else {
            Write-Host "Errore" -ForegroundColor Red
        }
        Write-Host "Accesso QMC:`t`t" -NoNewline
        if ($QMCTest) {
            Write-Host "Successo" -ForegroundColor Green
        } else {
            Write-Host "Errore" -ForegroundColor Red
        }
        Write-Host "Accesso hub:`t`t" -NoNewline
        if ($HubTest) {
            Write-Host "Successo" -ForegroundColor Green
        } else {
            Write-Host "Errore" -ForegroundColor Red
        }
    } elseif (($InstallationType -eq "NPrinting") -and ($_.TipoNodo -eq "Central")) {
        $ConsoleTest = Test-WebPage -Url "https://$($_.Hostname):4993"
        Write-Host "Accesso console:`t" -NoNewline
        if ($ConsoleTest -eq 200) {
            Write-Host "Successo" -ForegroundColor Green
        } else {
            Write-Host "Errore" -ForegroundColor Red
        }
    }
    Write-Host
}