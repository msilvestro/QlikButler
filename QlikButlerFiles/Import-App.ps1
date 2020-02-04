<#

.SINOSSI

    Script per l'importazione e la pubblicazione di una nuova app.

.DESCRIZIONE

    Lo script esegue le azioni necessarie per l'importazione e la pubblicazione di una nuova app.
    * Chiedi informazioni sull'app sorgente (fornita come qvf).
    * Importa l'app sorgente.
    * Effettua, se richiesto, il cambio di owner.
    * Chiedi informazioni sull'app e stream di destinazione.
    * In base alle informazioni fornite, effettua una nuova pubblicazione o una pubblicazione con replace.

.NOTE

    Autore: Matteo Silvestro
    Versione: 3.0.6
    Ultimo aggiornamento: 27/11/2019

#>

## Operazioni preliminari per il funzionamento dello script ##

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

# Importa le funzioni ausiliari per l'avvio e l'arresto dei servizi.
Import-Module $InstallPath\QlikButler\Data\QlikButlerToolbox.psm1

# Connessione all'ambiente.
$FQDN = ([System.Net.Dns]::GetHostByName($env:COMPUTERNAME)).Hostname
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
    Mostra le informazioni salienti di un'app.

.SINTASSI
    Out-App [-App] <QlikApp>

#>
function Out-App {

    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $App
    )

    $App | Select-Object -Property id, name, createdDate, @{name = 'ownerName'; expression = { $_.owner.name }}, publishTime, published, @{name = 'sizeMB'; expression = { "{0:N2} MB" -f ($_.fileSize / 1MB)}}, @{name = 'streamName' ;expression = { $_.stream.name }}, lastReloadTime

}

function Clean-QlikFilter {

    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Filter
    )

    return $Filter.Replace("'", "\'")

}

## Importa app ##


function Start-ImportPublishApp {
    param(
        [string] $SourceAppPath,
        [string] $Owner = "",
        [string] $TargetAppName = "",
        [string] $TargetAppStream = ""
    )

    # Chiedi il nome dell'app che verrà importata.
    $FileName = (Get-ChildItem $SourceAppPath).BaseName

    # Controlla la presenza di altre app con lo stesso nome, in tal caso aggiungi un numero progressivo alla fine del nome file.
    if (($TargetAppStream -eq "") -and ($TargetAppName -ne "")) {
        # Se viene specificato il nome dell'app target ma non lo stream, rinomina semplicemente l'app - non verrà poi effettuata la pubblicazione.
        $SourceAppName = $TargetAppName
    } else {
        # Nel caso standard chiama l'app con il nome del QVF.
        $SourceAppName = $FileName | Clean-QlikFilter
    }
    $SourceFilter = "name eq '$SourceAppName' and published eq false"
    $Tail = 0
    while ((Get-QlikApp -filter $SourceFilter).count -ne 0) {
        $Tail += 1
        $SourceFilter = "name eq '$($SourceAppName)_$Tail' and published eq false"
    }
    if ($Tail -ge 0) {
        $SourceAppName = "$($SourceAppName)_$Tail"
        Write-Host "App rinominata in '$SourceAppName'."
    }

    # Importa l'app sorgente.
    Write-Host "`r`n`r`nImportazione app" -BackgroundColor DarkCyan
    $SourceApp = (Import-QlikApp -file $SourceAppPath -name $SourceAppName -upload).Content | ConvertFrom-Json

    # Cambia l'owner.
    $OriginalOwner = $SourceApp.owner.name
    if (@(Get-QlikUser -filter "name eq '$Owner'").count -ne 1) {
        Write-Output "Impossibile trovare un'utenza univoca con il nome '$Owner'."
        $Owner = ""
    }
    if ($Owner -eq "") {
        $Owner = $OriginalOwner
        Write-Output "Il proprietario '$Owner' è rimasto invariato."
    } else {
        $SourceApp = Update-QlikApp -id $SourceApp.id -owner (Get-QlikUser -filter "name eq '$Owner'")
        Write-Output "Il nuovo proprietario dell'app è '$Owner'."
    }

    Write-Host "App importata" -ForegroundColor DarkCyan
    $SourceApp | Out-App


    ## Pubblica app ##

    if ($TargetAppStream -eq "") {
        # Se non viene specificata lo stream su cui pubblicare l'app, non effettuare la pubblicazione.
        exit
    }

    # Chiedi il nome dell'app target e lo stream su cui verrà pubblicato.
    $TargetFilter = "name eq '$($TargetAppName.Replace("'", "\'"))' and stream.name eq '$TargetAppStream'"

    $TargetApp = Get-QlikApp -filter $TargetFilter -full
    # In base al numero di app target trovate, esegui diverse azioni.
    if (@($TargetApp).count -eq 0) {

        # A) Non ci sono app con quel nome nello stream, stiamo quindi eseguendo una pubblicazione ex novo.
        Write-Host "L'app '$TargetAppName' sullo stream '$TargetAppStream' non esiste, l'app sorgente verrà pubblicata ex novo."
        #if ((Read-Host -Prompt "Pubblicare l'app? [S] Sì [N] No (Default 'N')") -ne "S") { exit }

        # Esegui la pubblicazione.
        Write-Host "`r`nPubblicazione app" -ForegroundColor DarkCyan
        Publish-QlikApp -id $SourceApp.id -name $TargetAppName -stream $TargetAppStream | Out-Null
        Get-QlikApp -filter $TargetFilter -full | Out-App

    } elseif (@($TargetApp).count -eq 1) {

        # B) C'è già un'app con quel nome nello stream, stiamo quindi eseguendo una pubblicazione con replace.
        Write-Host "L'app '$TargetAppName' sullo stream '$TargetAppStream' esiste, l'app sorgente verrà pubblicata con replace su di essa."
        #if ((Read-Host -Prompt "Pubblicare l'app? [S] Sì [N] No (Default 'N')") -ne "S") { exit }

        # Esegui il replace.
        Write-Host "`r`nPubblicazione app" -ForegroundColor DarkCyan
        Switch-QlikApp -id $SourceApp.id -appId $TargetApp.id | Out-Null
        Get-QlikApp -filter $TargetFilter -full | Out-App
    
    } elseif (@($TargetApp).count -gt 1) {

        # C) Ci sono almeno due app che corrispondono ai criteri, caso estremo che però pregiudica l'esecuzione dell'import.
        Write-Host "L'app '$TargetAppName' sullo stream '$TargetAppStream' non è univoca."
        exit

    }

}

## 
$SourceAppPaths = Get-FileByFileDialog -TypeFilter "App esportata (*.qvf)|*.qvf" -Multiselect

$SourceAppPaths | foreach {
    $FileName = (Get-ChildItem $_).BaseName
    Write-Host "`r`n$FileName" -BackgroundColor DarkCyan
    $OriginalOwner = $SourceApp.owner.name
    $Owner = Read-Host "Inserire il nuovo owner dell'app (vuoto per lasciarlo invariato)"
    while (($Owner -ne "") -and (@(Get-QlikUser -filter "name eq '$Owner'").count -ne 1)) {
        Write-Output "Impossibile trovare un'utenza univoca con il nome '$Owner'."
        $Owner = Read-Host "Inserire il nuovo owner dell'app (vuoto per lasciarlo invariato)"
    }

    $TargetAppName = Read-Host "Inserire il nome dell'app che verrà pubblicata"
    $TargetAppStream = Read-Host "Inserire il nome dello stream su cui effettuare la pubblicazione"

    while (@(Get-QlikStream -filter "name eq '$TargetAppStream'").count -ne 1) {
        Write-Output "Lo stream '$TargetAppStream' non esiste."
        $TargetAppStream = Read-Host "Inserire il nome dello stream su cui effettuare la pubblicazione"
    }

    Start-ImportPublishApp -SourceAppPath $_ -Owner $Owner -TargetAppName $TargetAppName -TargetAppStream $TargetAppStream
}