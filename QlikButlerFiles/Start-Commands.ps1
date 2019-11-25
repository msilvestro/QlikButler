<#

.SINOSSI

    Script per l'esecuzione di alcuni comandi minori.

.DESCRIZIONE

    Lo script esegue alcuni comandi minori, in particolare:
    * Imposta tutti i servizi in manual

.NOTE

    Autori: Matteo Silvestro (Consoft S.p.A.)
    Versione: 2.6.0
    Ultimo aggiornamento: 11/11/2019

#>

param(
    [string] $Command
)

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

Write-Host $Command

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