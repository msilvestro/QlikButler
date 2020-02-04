<#

.SINOSSI

    Script per la gestione di Qlik Butler su un cluster o un gruppo di essi.

.SINTASSI
    QlikButlerManager [-GetStatus] [-Uninstall] [-Install] [-Ambiente] <string> [-Acronimo <string>] [-InstallPath <string>] [-NoConfig] [-NoTasks]

.DESCRIZIONE

    Lo script esegue le seguenti operazioni relative a una o più installazioni Qlik Butler:
    * Ottieni lo stato di un'installazione Qlik Butler, ovvero la sua versione e lo stato delle schedulazioni.
      es. QlikButlerManager -GetStatus -Acronimo "ACRO0" -Ambiente "Prod"
    * Ottieni lo stato di tutte le installazioni Qlik Butler di un intero ambiente.
      es. QlikButlerManager -GetStatus -Ambiente "Prod"
    * Disinstalla Qlik Butler da un cluster, compresi eventualmente file di configurazione e/o schedulazioni.
      es. QlikButlerManager -Uninstall -Acronimo "ACRO0" -Ambiente "Prod" -NoConfig -NoTasks
    * Disinstalla Qlik Butler da un intero ambiente.
      es. QlikButlerManager -Uninstall -Ambiente "Prod" -NoConfig -NoTasks
    * Installa Qlik Butler su un cluster, creando anche eventualmente il file di configurazione e/o le schedulazioni.
      es. QlikButlerManager -Install -Acronimo "ACRO0" -Ambiente "Prod" -NoConfig -NoTasks
    * Installa Qlik Butler su un intero ambiente.
      es. QlikButlerManager -Install -Ambiente "Prod" -NoConfig -NoTasks
    * Si possono combinare i comandi descritti sopra, in particolare eseguendo sia disinstallazione che installazione queste operazioni verranno eseguite in tale ordine,
      ottenendo come risultato un aggiornamento dell'installazione Qlik Butler.

.NOTE

    Autore: Matteo Silvestro
    Versione: 2.3.0
    Ultimo aggiornamento: 27/08/2019

#>

param(
    [string] $Acronimo,
    [string] $Ambiente,
    [string] $InstallationType,
    [switch] $Uninstall = $false,
    [switch] $Install = $false,
    [switch] $NoConfig = $false,
    [switch] $NoTasks = $false,
    [string] $InstallPath = "E:\Software\__PWSH"
)


# Ottieni la directory da cui è stato lanciato lo script.
$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

Import-Module $ScriptPath\QlikButlerManagerToolbox.psm1

if ($Uninstall) {
    Uninstall-QlikButler -Acronimo $Acronimo -Ambiente $Ambiente -InstallationType $InstallationType -NoTasks:$NoTasks -NoConfig:$NoConfig
}

if ($Install) {
    Install-QlikButler -Acronimo $Acronimo -Ambiente $Ambiente -InstallationType $InstallationType -NoTasks:$NoTasks -NoConfig:$NoConfig
}