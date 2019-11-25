<#

.SINOSSI

    Script per il backup e la successiva importazione di nuove Security Rules.

.DESCRIZIONE

    Lo script esegue le azioni necessarie per l'importazione di nuove Security Rules.
    * Crea una nuova cartella relativa al giorno corrente in cui salvare i backup.
    * Richiedi il file JSON da importare (da mettere nella cartella dei backup corrente).
    * Esegui il backup delle Security Rules attuali (solo Custom e tutte).
    * Rimuovi le Security Rules vecchie, se l'utente conferma.
    * Importa le nuove Security Rules dal file JSON.
    * Esegui nuovamente un backup di tutte le Security Rules.
    * Confronta le Security Rules importate e il file JSON per rilevare eventuali discrepanze.

.NOTE

    Autori: Matteo Silvestro (Consoft S.p.A.)
    Versione: 2.3.7
    Ultimo aggiornamento: 28/08/2019

#>

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

<#

.SINOSSI
    Aggiungi un numero progressivo alla fine del nome di un file, in modo da evitare doppioni.
    Per esempio, se esiste già un file "test.json", verrà usato il nome "test_1.json".

.SINTASSI
    Add-ProgressiveNumber [-FileName] <string>

#>
function Add-ProgressiveNumber {

    param (
        [string] $FileName
    )

    if (Test-Path $FileName) {
        $PathPreExt = "$((Get-Item $FileName).DirectoryName)\$((Get-Item $FileName).BaseName)"
        $PathExt = (Get-Item $FileName).Extension
        $Tail = ""
        $Number = 0
        while (Test-Path -Path "$PathPreExt$Tail$PathExt") {
            $Number += 1
            $Tail = "_$Number"
        }
        return "$PathPreExt$Tail$PathExt"
    } else {
        return $FileName
    }

}

# Connessione all'ambiente.
try {
    Connect-Qlik -ComputerName $env:COMPUTERNAME -UseDefaultCredentials -TrustAllCerts | Out-Null
} catch {
    Write-Host "Impossibile connettersi a $env:COMPUTERNAME." -BackgroundColor Red
    if (-not $psise) { Read-Host "`r`nPremere invio per chiudere" }
    exit
}

# Crea una cartella di backup per la data attuale, se non esiste già.
$Date = Get-Date -UFormat "%Y_%m_%d"
$SecurityRulesFolder = "$InstallPath\QlikButler\SecurityRules\$Date"
if (-not (Test-Path -Path $SecurityRulesFolder)) {
    New-Item -Path $SecurityRulesFolder -ItemType Directory | Out-Null
    Write-Host "Creata cartella '$SecurityRulesFolder'."
}

# Esegui prima il backup di:
# 1) tutte le Security Rules Custom e abilitate;
# 2) tutte le Security Rules.
Write-Host "`r`nEsecuzione backup Security Rules" -BackgroundColor DarkCyan
# 1
$CustomFilter = "type eq 'custom' and category eq 'security' and name ne 'DataPrepAppCacheAccessRule'"
Get-QlikRule -filter $CustomFilter -full -raw | ConvertTo-Json | Out-File (Add-ProgressiveNumber -FileName "$SecurityRulesFolder\$env:COMPUTERNAME-Backup-CustomSecRules-$Date.json")
Write-Host "Eseguito backup delle Security Rules con filtro `"$CustomFilter`"."
# 2
Get-QlikRule -filter "category eq 'security'" -full -raw | ConvertTo-Json | Out-File (Add-ProgressiveNumber -FileName "$SecurityRulesFolder\$env:COMPUTERNAME-Backup-AllSecRules-$Date.json")
Write-Host "Eseguito backup integrale delle Security Rules."

if ((Read-Host "`r`nEseguire importazione di nuove Security Rules? [S] Sì [N] No (Default 'N')") -ne "S") {
    Start-Process $SecurityRulesFolder
    exit
}

# Procedi con l'importazione.
Read-Host -Prompt "Verrà aperta la posizione in cui inserire il file con le nuove Security Rules ($SecurityRulesFolder) [Premere qualsiasi tasto per continuare]"
Start-Process $SecurityRulesFolder
$NewSecurityRulesFile = Read-Host -Prompt "Inserire il nome del file posizionato in '$SecurityRulesFolder'"
if (-not (Test-Path $SecurityRulesFolder\$NewSecurityRulesFile)) {
    if (-not (Test-Path "$SecurityRulesFolder\$NewSecurityRulesFile.json")) {
        Throw "Il file '$SecurityRulesFolder\$NewSecurityRulesFile' non esiste."
    } else {
        $NewSecurityRulesFile = "$NewSecurityRulesFile.json"
    }
}

# Prima di procedere, elimina tutte le Security Rules Custom e abilitate (eventualmente anche le non abilitate, in base al file JSON di input).
# In caso contrario, verranno duplicate tutte.
Write-Host "`r`nRimozione Security Rules vecchie" -BackgroundColor DarkCyan
Write-Host "Le seguenti Security Rules verrano rimosse:" # TODO togliere DataPrepAppCache
$SecurityRulesToRemove = Get-QlikRule -filter $CustomFilter
$SecurityRulesToRemove | Sort-Object -Property name | Format-Table -AutoSize -Property name, type, disabled
Write-Host ("Verranno rimosse {0} Security Rules." -f $SecurityRulesToRemove.Length)

if ((Read-Host -Prompt "Procedere all'eliminazione? [S] Sì [N] No (Default 'N')") -eq "S") {

    # Se l'utente ha deciso di sì, esegui la rimozione delle Security Rules.
    $SecurityRulesToRemove | Remove-QlikRule | Out-Null
    Write-Host "Le Security Rules con filtro `"$CustomFilter`" sono state rimosse."

    # Importa le Security Rules.
    # Nell'importazione vengono ignorati alcuni campi, tra cui anche il "seedId" che, se non è diverso da "00000000-0000-0000-0000-000000000000", genera un errore 403.
    # Inoltre, viene ignorata la Security Rule "DataPrepAppCacheAccessRule" che in realtà è una regola di Default e non va quindi modificata.
    Write-Host "`r`nEsecuzione importazione nuove Security Rules" -BackgroundColor DarkCyan
    $SecurityRulesJson = Get-Content -raw "$SecurityRulesFolder\$NewSecurityRulesFile" | ConvertFrom-Json
    $SecurityRulesJson | ForEach-Object {
        $SecurityRuleName = $_.name
        try {
            $_ | where { $_.name -ne "DataPrepAppCacheAccessRule" } | select -Property * -ExcludeProperty id, tags, createdDate, modifiedDate, modifiedByUserName, seedId | Import-QlikObject | Out-Null
            Write-Host "Importata con successo: $SecurityRuleName"
        } catch {
            Write-Host "Errore nell'importazione: $SecurityRuleName" -BackgroundColor Red
        }
    }
    Write-Host "`r`nEseguita importazione Security Rules."

    # Confronta Security Rules importate e file JSON di partenza.
    Write-Host "`r`nControllo risultati importazione" -BackgroundColor DarkCyan
    Write-Host "Confronto tra file JSON e Security Rules importate per verificare la loro correttezza importazione."
    $StartingRules = Get-Content -raw "$SecurityRulesFolder\$NewSecurityRulesFile" | ConvertFrom-Json
    $FinalRules = Get-QlikRule -filter "category eq 'security' and type eq 'custom'" -full -raw

    $CorrectNumber = 0
    $TotalNumber = 0
    $StartingRules | ForEach-Object {
        $TotalNumber += 1
        $Sample = $_
        $MatchingRules = ($FinalRules | Where-Object { $_.name -eq $Sample.name })
        $Matches = @($MatchingRules).Count # forza la conversione in array, nel caso ci fosse un singolo oggetto o non ce ne fossero
        if ($Matches -eq 0) { # non sono state restituite regole coincidenti
            Write-Host "[0] Regola non importata: $($Sample.name)" -BackgroundColor Red
        } elseif ($Matches -eq 1) {
            $Diff = $false
            foreach ($Prop in @("name", "category", "type", "rule", "resourceFilter", "actions", "comment", "disabled", "ruleContext")) {
                if ($Sample.($Prop) -ne $MatchingRules.($Prop)) {
                    if (-not $Diff) {
                        $Diff = $true
                        Write-Host "[1] Regola con differenze: $($Sample.name)" -BackgroundColor Red
                    }
                    Write-Host "$Prop -> JSON:`t$($Sample.($Prop))"
                    Write-Host "$Prop -> SecRul:`t$($MatchingRules.($Prop))"
                }
            }
            if (-not $Diff) {
                $CorrectNumber += 1
            }
        } elseif ($Matches -gt 1) {
            Write-Host "[2] Regola duplicata: $($Sample.name)" -BackgroundColor Red
        }
    }
    Write-Host "`r`nSecurity Rules importante con successo: $CorrectNumber su $TotalNumber."

} else {
    Write-Host "Procedura interrotta."
}