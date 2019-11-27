<#

.SINOSSI

    Script per l'importazione delle extensions.

.DESCRIZIONE

    Lo script esegue le azioni necessarie per l'importazione di una nuova extension, sostituendola se già presente.

.NOTE

    Autori: Matteo Silvestro (Consoft S.p.A.)
    Versione: 3.0.5
    Ultimo aggiornamento: 27/11/2019

#>

## Operazioni preliminari per il funzionamento dello script ##

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

# Importa le funzioni ausiliari per l'avvio e l'arresto dei servizi.
Import-Module $InstallPath\QlikButler\Data\QlikButlerToolbox.psm1

# Connessione all'ambiente.
$FQDN = ([System.Net.Dns]::GetHostByName(($env:COMPUTERNAME))).Hostname
try {
    $Domain = (Get-ADDomain).NetBIOSName
    Connect-Qlik -ComputerName $FQDN -UseDefaultCredentials -TrustAllCerts | Out-Null
} catch {
    Write-Host "Impossibile connettersi a '$FQDN'." -BackgroundColor Red
    if (-not $psise) { Read-Host "`r`nPremere invio per chiudere" }
    exit
}

<#

.SINOSSI
    Mostra le informazioni salienti di un'extension.

.SINTASSI
    Out-Extension [-Extension] <QlikExtension>

#>
function Out-Extension {

    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Extension
    )

    $Extension | Select-Object -Property id, name, createdDate, @{name = 'ownerName'; expression = { $_.owner.name }}

}

## Chiedi il file dell'extension ##

$ExtensionPath = Get-FileByFileDialog -TypeFilter "Extension (*.zip)|*.zip"
if (-not $ExtensionPath) {
    exit
}

# Ottieni il nome dell'Extension come verrà visualizzata sulla QMC.
# https://help.qlik.com/en-US/sense/June2019/Subsystems/ManagementConsole/Content/Sense_QMC/import-extensions.htm#anchor-1
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
$Content = [IO.Compression.ZipFile]::OpenRead($ExtensionPath)
$FileName = ($Content.Entries | Where-Object { $_.Name -like "*.qext" }).Name
$ExtensionName = $FileName.Substring(0, $FileName.Length - 5)
$Content.Dispose()

Write-Output "Trovata extension '$ExtensionName'."

$ExtensionExists = Get-QlikExtension -Filter "name eq '$ExtensionName'"
if ($ExtensionExists) {
    Write-Output "Extension '$ExtensionName' già presente nel sistema."
    Remove-QlikExtension -ename $ExtensionName
    Write-Output "Extension rimossa."
} else {
    Write-Output "Extension '$ExtensionName' nuova."
}
Import-QlikExtension -ExtensionPath $ExtensionPath | Out-Null

# Cambia l'owner.
$Owner = Get-QlikUser -filter "name eq 'qlikadministrator'"
Update-QlikExtension -id (Get-QlikExtension -Filter "name eq '$ExtensionName'").id -owner "$($Owner.userDirectory)\$($Owner.userId)" | Out-Null

Write-Output "Extension creata:"
Get-QlikExtension -Filter "name eq '$ExtensionName'" -Full | Out-Extension