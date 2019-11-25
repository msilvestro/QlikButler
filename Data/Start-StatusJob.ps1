<#

.SINOSSI

    Controlla lo stato di un cluster o di un nodo.

.SINTASSI

    Start-StatusJob [-Type] <string> [-Acronimo] <string> [-Ambiente] <string>  [-InstallationType] <string> [[-Hostname] <string>] [[-TipoNodo] <string>]

.DESCRIZIONE

    In base al tipo di richiesta:
    * Version: Ottieni la versione di Qlik Butler installata sul cluster.
    * BackupStatus: Ottieni lo stato dell'ultimo backup del cluster.
    * Status: Ottieni lo stato di raggiungibilità del nodo.

.NOTE

    Autori: Matteo Silvestro (Consoft S.p.A.)
    Versione: 3.0.2
    Ultimo aggiornamento: 11/10/2019

 #>

param(
        [string] $Type,
        [string] $Ambiente,
        [string] $Acronimo,
        [string] $Installazione,
        [string] $Hostname = $null,
        [string] $TipoNodo = $null
    )

$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

Import-Module $ScriptPath\QlikButlerManagerToolbox.psm1
#Import-Module $ScriptPath\..\QlikButlerFiles\Data\QlikButlerToolbox.psm1

if ($Type -eq "Version") {
    Get-ClusterQlikButlerVersion -Ambiente $Ambiente -Acronimo $Acronimo -InstallationType $Installazione -GetVersion -GetTasks
} elseif ($Type -eq "BackupStatus") {
    Get-ClusterBackupStatus -Ambiente $Ambiente -Acronimo $Acronimo -InstallationType $Installazione
} elseif ($Type -eq "Status") {
    try {
        if ($Installazione -eq "Qlik Sense") {
            #$HealthCheck = Test-QlikSenseAccess -Hostname $Hostname -Ambiente $Ambiente
            $HealthCheck = Test-WebPage -Url "https://$Hostname/engine/healthcheck/"
            if ($HealthCheck) {
                "Raggiungibile"
            } else {
                "Non raggiungibile"
            }
        }
        elseif ($Installazione -eq "NPrinting") {
            if ($TipoNodo -eq "Central") {
                if (Test-WebPage -Url "https://$($Hostname):4993") {
                    "Raggiungibile"
                } else {
                    "Non raggiungibile"
                }
            } elseif ($TipoNodo -eq "Rim") {
                if ((Test-NetConnection -ComputerName $Hostname).PingSucceeded) {
                    "Raggiungibile"
                } else {
                    "Non raggiungibile"
                }
            }
        }
    } catch {
        $false
    }
}