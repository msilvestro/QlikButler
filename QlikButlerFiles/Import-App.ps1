<#

.SINOSSI

    Script per l'importazione e la pubblicazione di una nuova app.

.DESCRIZIONE

    Lo script esegue le azioni necessarie per l'importazione e la pubblicazione di una nuova app.
    * Chiedi informazioni sull'app sorgente (fornita come qvf).
    * Importa l'app sorgente.
    * Effettua, se richiesto, il cambio di owner.
    * Chiedi se effettuare una nuova pubblicazione o una pubblicazione con replace.
    * Chiedi informazioni sull'app e stream di destinazione.
    * Esegui un backup dell'app di destinazione (solo in caso di replace).
    * Pubblica la nuova app.

.NOTE

    Autori: Matteo Silvestro (Consoft S.p.A.)
    Versione: 2.3.8
    Ultimo aggiornamento: 28/08/2019

#>

<#

.SINOSSI
    Mostra le informazioni salienti di un'app.

.SINTASSI
    Out-App [-App] <QlikApp>

#>
function Out-App {

    param (
        $App
    )

    $App | Select-Object -Property id, name, createdDate, @{name = 'ownerName'; expression = { $_.owner.name }}, publishTime, published, @{name = 'sizeMB'; expression = { "{0:N2} MB" -f ($_.fileSize / 1MB)}}, @{name = 'streamName' ;expression = { $_.stream.name }}, lastReloadTime

}

# Connessione all'ambiente.
try {
    Connect-Qlik -ComputerName $env:COMPUTERNAME -UseDefaultCredentials -TrustAllCerts | Out-Null
} catch {
    Write-Host "Impossibile connettersi a $env:COMPUTERNAME." -BackgroundColor Red
    if (-not $psise) { Read-Host "`r`nPremere invio per chiudere" }
    exit
}

$SourceAppPath = Read-Host "Inserire percorso completo dell'app da importare"
if (-not (Test-Path $SourceAppPath)) {
    if (-not (Test-Path "$SourceAppPath.qvf")) { # l'utente potrebbe aver omesso l'estensione
        if (-not (Test-Path "\\tsclient\C\_appoggio\$SourceAppPath")) { # controlla anche nella cartella di appoggio
            if (-not (Test-Path "\\tsclient\C\_appoggio\$SourceAppPath.qvf")) { # anche senza estensione
                Throw "Il file '$SourceAppPath' non esiste."
            } else {
                $SourceAppPath = "\\tsclient\C\_appoggio\$SourceAppPath.qvf"
            }
        } else {
            $SourceAppPath = "\\tsclient\C\_appoggio\$SourceAppPath"
        }
    } else {
        $SourceAppPath = "$SourceAppPath.qvf"
    }
}
$NomeFile = (Get-ChildItem $SourceAppPath).BaseName
$SourceAppName = Read-Host "Inserire il nome dell'app da importare (lasciare vuoto per chiamarla '$NomeFile')"
if ($SourceAppName -eq "") {
    $SourceAppName = $NomeFile
}
# ATTENZIONE! I filtri non devono avere apici singoli altrimenti restituisce errore 400 Bad Request.
#$SourceAppName = $SourceAppName.Replace("'", "\'")

$SourceFilter = "name eq '$($SourceAppName.Replace("'", "\'"))' and published eq false"
while ((Get-QlikApp -filter $SourceFilter).count -ne 0) {
    $Risposta = Read-Host "L'app chiamata '$SourceAppName' esiste già. [C = Cancella, R = Rinomina, altrimenti annulla]"
    if ($Risposta -eq "C") {
        Get-QlikApp -filter $SourceFilter | Remove-QlikApp
    } elseif ($Risposta -eq "R") {
        $SourceAppName = ""
        while ($SourceAppName -eq "") {
            $SourceAppName = Read-Host "Inserire il nuovo nome dell'app"
        }
        $SourceFilter = "name eq '$($SourceAppName.Replace("'", "\'"))' and published eq false"
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
Out-App $SourceApp

$Mode = Read-Host "Eseguire pubblicazione o replace? [P = Pubblicazione, R = Replace, altrimenti annulla]"
if (($Mode -ne "P") -and ($Mode -ne "R")) {
    exit
}

# In caso di pubblicazione è inutile chiedere questa informazione, se si vuole modificare il nome dell'app pubblicata basta prenderlo da $SourceAppName
if ($Mode -eq "R") {
    $TargetAppName = Read-Host "Inserire il nome dell'app su cui effettuare la pubblicazione"
} else {
    $TargetAppName = $SourceAppName
}
# Chiedi lo strema target e controlla che esista.
$TargetAppStream = Read-Host "Inserire il nome dello stream su cui effettuare la pubblicazione"
while (@(Get-QlikStream -filter "name eq '$TargetAppStream'").count -ne 1) {
    Write-Output "Lo stream '$TargetAppStream' non esiste."
    $TargetAppStream = Read-Host "Inserire il nome dello stream su cui effettuare la pubblicazione"
}
$TargetFilter = "name eq '$($TargetAppName.Replace("'", "\'"))' and stream.name eq '$TargetAppStream'"

if ($Mode -eq "R") {
    if ((Get-QlikApp -filter $TargetFilter).count -eq 0) {
        throw "L'app '$TargetAppName' sullo stream '$TargetAppStream' non esiste."
    } elseif ((Get-QlikApp -filter $TargetFilter).count -gt 1) {
        throw "L'app '$TargetAppName' sullo stream '$TargetAppStream' non è univoca."
    }
} elseif ($Mode -eq "P") {
    while ((Get-QlikApp -filter $TargetFilter).count -ne 0) {
        $Risposta = Read-Host "L'app chiamata '$TargetAppName' esiste già. [C = Cancella, R = Rinomina, altrimenti annulla]"
        if ($Risposta -eq "C") {
            Get-QlikApp -filter $TargetFilter | Remove-QlikApp
        } elseif ($Risposta -eq "R") {
            $TargetAppName = ""
            while ($TargetAppName -eq "") {
                $TargetAppName = Read-Host "Inserire il nuovo nome dell'app"
            }
            $TargetFilter = "name eq '$($TargetAppName.Replace("'", "\'"))' and stream.name eq '$TargetAppStream'"
        } else {
            throw "L'app '$TargetAppName' esiste già."
        }
    }
}

if ($Mode -eq "R") {

    $TargetApp = Get-QlikApp -filter $TargetFilter -full

    if ((Read-Host -Prompt "Eseguire backup dell'app? [S] Sì [N] No (Default 'N')") -eq "S") {
        # Esegui il backup dell'app target.
        Write-Host "`r`nBackup app" -ForegroundColor DarkCyan
        $Date = Get-Date -UFormat "%Y%m%d"
        $BackupApp = Copy-QlikApp -id $TargetApp.id -name "$($TargetApp.name)_bck_$Date"
        Out-App $BackupApp
        ## TODO controllare che corrisponda all'app di partenza.
    }

    if ((Read-Host -Prompt "Pubblicare l'app? [S] Sì [N] No (Default 'N')") -eq "S") {
        # Esegui il replace.
        Write-Host "`r`nPubblicazione app" -ForegroundColor DarkCyan
        Switch-QlikApp -id $SourceApp.id -appId $TargetApp.id | Out-Null
        Out-App (Get-QlikApp -filter $TargetFilter -full)
        # TODO controllare che l'app sia stata pubblicata correttamente
    }

} elseif ($Mode -eq "P") {

    if ((Read-Host -Prompt "Pubblicare l'app? [S] Sì [N] No (Default 'N')") -eq "S") {
        # Esegui la pubblicazione.
        Write-Host "`r`nPubblicazione app" -ForegroundColor DarkCyan
        Publish-QlikApp -id $SourceApp.id -name $SourceAppName -stream $TargetAppStream | Out-Null
        Out-App (Get-QlikApp -filter $TargetFilter -full)
    }

}