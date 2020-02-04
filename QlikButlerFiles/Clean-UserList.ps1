<#

.SINOSSI

    Rimuovi gli utenti non attivi per evitare che vengano salvati dati riservati (per rispettare il GDPR).

.NOTE

    Autori: Matteo Silvestro
    Versione: 3.0.8
    Ultimo aggiornamento: 04/02/2020

#>

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

# Connessione all'ambiente.
try {
    Connect-Qlik -ComputerName $env:COMPUTERNAME -UseDefaultCredentials -TrustAllCerts | Out-Null
} catch {
    Write-Host "Impossibile connettersi a $env:COMPUTERNAME." -BackgroundColor Red
    if (-not $psise) { Read-Host "`r`nPremere invio per chiudere" }
    exit
}

# File di log.
$Log = "$InstallPath\Logs\PuliziaListaUtenti.log"
$LogContent = "# $(Get-Date -UFormat "%Y_%m_%d__%H_%M_%S") - Pulizia utenti #"

# Seleziona gli utenti da rimuovere.
$UsersToRemove = Get-QlikUser -full -filter "removedExternally eq true or inactive eq true"

if ($UsersToRemove.Count -gt 0) {
    # Rimuovi gli utenti e scrivi il log solo se non c'è almeno un utente da rimuovere.
    $UsersToRemove | foreach {
        if (-not $_.roles) { # se l'utente non ha un ruolo associato, rimuovilo
            $Message = "Rimosso $($_.userId)..."
            Write-Output $Message
            $LogContent += "`r`n$Message"
            Remove-QlikUser -id $_.id
        }
    }

    $LogContent | Add-Content -Path $Log
} else {
    Write-Output "Nessun utente da rimuovere."
}