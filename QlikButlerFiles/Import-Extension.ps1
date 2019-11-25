<#

.SINOSSI

    Script per l'importazione delle extensions.

.DESCRIZIONE

    Lo script esegue le azioni necessarie per l'importazione di una nuova extension, sostituendola se già presente.

.NOTE

    Autori: Matteo Silvestro (Consoft S.p.A.)
    Versione: 2.6.2
    Ultimo aggiornamento: 19/11/2019

#>

# Connessione all'ambiente.
Connect-Qlik -ComputerName $env:COMPUTERNAME -UseDefaultCredentials -TrustAllCerts

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

$ExtensionZip = "\\tsclient\C\_appoggio\PRQK0_ZoomSense_V14"

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

Add-Type -AssemblyName System.Windows.Forms
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('MyDocuments');
    Filter = "Extension (*.zip)|*.zip"
}
$FileBrowserResult = $FileBrowser.ShowDialog()
if ($FileBrowserResult -eq "OK") {
    $ExtensionPath = $FileBrowser.FileName
    Write-Host "Selezionato il file '$ExtensionPath'."
} elseif ($FileBrowserResult -eq "Cancel") {
    Write-Host "Operazione annullata."
    exit
} else {
    Write-Host "Errore '$FileBrowserResult'."
    exit
}

# Ottieni il nome dell'Extension come verrà visualizzata sulla QMC.
# https://help.qlik.com/en-US/sense/June2019/Subsystems/ManagementConsole/Content/Sense_QMC/import-extensions.htm#anchor-1
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
Write-Output "Extension creata:"
Get-QlikExtension -Filter "name eq '$ExtensionName'" -Full