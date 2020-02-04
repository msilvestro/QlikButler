<#

.SINOSSI

    Script per l'esecuzione di alcuni comandi minori.

.DESCRIZIONE

    Lo script esegue alcuni comandi minori, in particolare:
    * Imposta tutti i servizi in manual.
    * Imposta tutti i servizi in automatic.
    * Arresta e disabilita servizi superflui.
    * Installa Qlik Cli.

.NOTE

    Autore: Matteo Silvestro
    Versione: 3.0.6
    Ultimo aggiornamento: 27/01/2020

#>

param(
    [string] $Command
)

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

Write-Host $Command -BackgroundColor DarkCyan

# Importa le funzioni ausiliari per l'avvio e l'arresto dei servizi.
Import-Module $InstallPath\QlikButler\Data\QlikButlerToolbox.psm1

if ($Command -eq "Imposta tutti i servizi in manual") {
    foreach ($Service in (Get-Service Qlik*).Name) {
        Write-Output "Messa in manual del servizio $Service..."
        Set-Service -Name $Service -StartupType Manual
        $StartMode = (Get-WmiObject -Class Win32_Service -Property StartMode -Filter "Name='$Service'").StartMode
        Write-Output "-> $Service in modalità: $StartMode."
    }
} elseif ($Command -eq "Imposta tutti i servizi in automatic") {
    foreach ($Service in (Get-Service Qlik*).Name) {
        Write-Output "Messa in manual del servizio $Service..."
        Set-Service -Name $Service -StartupType Automatic
        $StartMode = (Get-WmiObject -Class Win32_Service -Property StartMode -Filter "Name='$Service'").StartMode
        Write-Output "-> $Service in modalità: $StartMode."
    }
} elseif ($Command -eq "Arresta e disabilita servizi superflui") {
    # Ottieni solo i servizi che sono avviati ma non dovrebbero esserlo (perché disabilitati nella configurazione della QMC).
    $QlikServices = @()
    @(
        "QlikSenseRepositoryDatabase",
        "QlikSenseRepositoryService",
        "QlikSenseProxyService",
        "QlikSenseEngineService",
        "QlikSenseSchedulerService",
        "QlikSensePrintingService",
        "QlikSenseServiceDispatcher",
        "QlikLoggingService"
    ) |  where { $_ -notin (Get-QlikService) } | foreach {
        $Service = Get-Service -Include $_ | where { $_.Status -eq "Running" }
        if ($Service) { $QlikServices += $Service.Name }
    }
    # Disabilita e arresta i servizi non pertinenti.
    $QlikServices | foreach {
        $Service = $_
        Write-Output "Arresto servizio $Service..."
        try {
            Set-Service -Name $Service -StartupType Disable
            Stop-Service -Name $Service -Force -ErrorAction Stop
        } catch {
            Write-Output "! Errore nell'arresto del servizio."
        }
        $Status = (Get-Service -Name $Service).Status
        Write-Output "-> $Service in stato: $Status."
    }
} elseif ($Command -eq "Installa Qlik Cli") {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

    # Chiedi il file zip contentente le Qlik-Cli.
    Add-Type -AssemblyName System.Windows.Forms
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        InitialDirectory = [Environment]::GetFolderPath('MyDocuments');
        Filter = "Archivio compresso (*.zip)|*.zip"
    }
    $FileBrowserResult = $FileBrowser.ShowDialog()
    if ($FileBrowserResult -eq "OK") {
        $Source = $FileBrowser.FileName
        Write-Host "Selezionato il file '$SourceAppPath'."
    } elseif ($FileBrowserResult -eq "Cancel") {
        Write-Host "Operazione annullata."
        exit
    } else {
        Write-Host "Errore '$FileBrowserResult'."
        exit
    }

    $Destination = "C:\Program Files\WindowsPowerShell\Modules"
    $Overwrite = $true

    if (-not (Test-Path $Destination\Qlik-Cli)) {
        New-Item -Path $Destination\Qlik-Cli -ItemType Directory | Out-Null
        Write-Host "Creata cartella '$Destination\Qlik-Cli'."
    } else {
        Remove-Item -Path $Destination\Qlik-Cli -Recurse
        Write-Host "Rimossa cartella '$Destination\Qlik-Cli'."
    }

    Write-Output "Installazione Qlik Cli..."
    $Content = [IO.Compression.ZipFile]::OpenRead($Source).Entries
    $Content | ForEach-Object -Process {
        $FilePath = Join-Path -Path $Destination -ChildPath $_
        Write-Output $FilePath
        if ($FilePath.Substring($FilePath.Length - 1, 1) -eq "\") {
            # È una directory.
            New-Item -Path $FilePath -ItemType Directory | Out-Null
        } else {
            # È un file.
            [IO.Compression.ZipFileExtensions]::ExtractToFile($_, $FilePath, $Overwrite)
        }
    }

    # Rinomina la cartella in modo che abbia il nome corretto.
    Move-Item -Path $Destination\Qlik-Cli-master -Destination $Destination\Qlik-Cli
    Write-Host "Cartella rinominata da '$Destination\Qlik-Cli-master' a '$Destination\Qlik-Cli'."
}