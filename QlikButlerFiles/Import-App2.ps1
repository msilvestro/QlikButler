<#

.SINOSSI
    Mostra le informazioni salienti di un'app.

.SINTASSI
    Out-App [-App] <QlikApp>

#>
function Out-App {

    [CmdletBinding()]
    param (
        $App
    )

    $App | Select-Object -Property id, name, createdDate, @{name = 'ownerName'; expression = { $_.owner.name }}, publishTime, published, @{name = 'sizeMB'; expression = { "{0:N2} MB" -f ($_.fileSize / 1MB)}}, @{name = 'streamName' ;expression = { $_.stream.name }}, lastReloadTime

}

function Clean-QlikFilter {

    [CmdletBinding()]
    param (
        [string] $Filter
    )

    return $Filter.Replace("'", "\'")

}

# Connessione all'ambiente.
$FQDN = ([System.Net.Dns]::GetHostByName(($env:COMPUTERNAME))).Hostname
try {
    $Domain = (Get-ADDomain).NetBIOSName
    Connect-Qlik -ComputerName $FQDN -Username $Domain\qlikadministrator | Out-Null
} catch {
    Write-Host "Impossibile connettersi a '$FQDN'." -BackgroundColor Red
    if (-not $psise) { Read-Host "`r`nPremere invio per chiudere" }
    exit
}

## Importa app ##

# Chiedi il nome del file qvf da importare.
Add-Type -AssemblyName System.Windows.Forms
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('MyDocuments');
    Filter = "App esportata (*.qvf)|*.qvf"
}
$FileBrowserResult = $FileBrowser.ShowDialog()
if ($FileBrowserResult -eq "OK") {
    $SourceAppPath = $FileBrowser.FileName
    Write-Host "Selezionato il file '$SourceAppPath'."
} elseif ($FileBrowserResult -eq "Cancel") {
    Write-Host "Operazione annullata."
    exit
} else {
    Write-Host "Errore '$FileBrowserResult'."
    exit
}

# Chiedi il nome dell'app che verrà importata.
$FileName = (Get-ChildItem $SourceAppPath).BaseName
$SourceAppName = Read-Host "Inserire il nome dell'app che verrà importata (lasciare vuoto per chiamarla '$FileName')"
if ($SourceAppName -eq "") {
    $SourceAppName = $FileName
}

# Controlla la presenza di altre app con lo stesso nome.
$SourceFilter = "name eq '$($SourceAppName | Clean-QlikFilter)' and published eq false"
while ((Get-QlikApp -filter $SourceFilter).count -ne 0) {
    $Risposta = Read-Host "L'app chiamata '$SourceAppName' esiste già. [C = Cancella, R = Rinomina, altrimenti annulla]"
    if ($Risposta -eq "C") {
        Get-QlikApp -filter $SourceFilter | Remove-QlikApp
    } elseif ($Risposta -eq "R") {
        $SourceAppName = ""
        while ($SourceAppName -eq "") {
            $SourceAppName = Read-Host "Inserire il nuovo nome dell'app"
        }
        $SourceFilter = "name eq '$($SourceAppName | Clean-QlikFilter)' and published eq false"
    } else {
        throw "L'app '$SourceAppName' esiste già."
    }
}

# Importa l'app sorgente.
Write-Host "`r`n`r`nImportazione app" -BackgroundColor DarkCyan
$SourceApp = Import-QlikApp -file $SourceAppPath -name $SourceAppName -upload

# Cambia l'owner.
$OriginalOwner = $SourceApp.owner.name
$Owner = Read-Host "Inserire il nuovo owner dell'app (lasciare vuoto per mantenere '$OriginalOwner')"
while (($Owner -ne "") -and (@(Get-QlikUser -filter "name eq '$Owner'").count -ne 1)) {
    Write-Output "Impossibile trovare un'utenza univoca con il nome '$Owner'."
    $Owner = Read-Host "Inserire il nuovo owner dell'app (lasciare vuoto per mantenere '$OriginalOwner')"
}
if ($Owner -eq "") { $Owner = $OriginalOwner }
$SourceApp = Update-QlikApp -id $SourceApp.id -ownername $Owner

Write-Host "App importata" -ForegroundColor DarkCyan
$SourceApp | Out-App