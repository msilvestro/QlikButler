<#

.SINOSSI

    Script per il backup del database di un'installazione Qlik Sense o NPrinting.

.DESCRIZIONE

    Lo script esegue le azioni necessarie per il backup in sicurezza di Qlik Sense o NPrinting.
    * Arresta i servizi di tutti i nodi del cluster, prima sui rim e poi sui central.
    * Esegui il backup del database - nel caso di Qlik Sense, sia del Repository Database (dump) sia dell'intero database (dumpall).
    * Avvia i servizi di tutti i nodi del cluster, prima sui central e poi sui rim.
    * Controlla la raggiungibilità dell'Hub di Qlik Sense oppure della console web NPrinting.
    * In caso contrario, tenta un altro riavvio dei servizi del cluster.

.NOTE

    Autori: Matteo Silvestro (Consoft S.p.A.)
    Versione: 3.0.7
    Ultimo aggiornamento: 29/01/2020

#>

param(
    [switch] $ManualBackup = $false
)

### Preparazione variabili necessarie per lo script ###

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

# Importa le funzioni ausiliari per l'avvio e l'arresto dei servizi.
Import-Module $InstallPath\QlikButler\Data\QlikButlerToolbox.psm1

# Carica i file di configurazione.
$ClusterConfig = Import-ConfigFile -ConfigFile $InstallPath\QlikButler\Data\Cluster.config
$SystemConfig = Import-ConfigFile -ConfigFile $InstallPath\QlikButler\Data\System.config

# Elenco variabili che variano in base all'ambiente, estratte dal file di configurazione.
$Ambiente = $ClusterConfig.Ambiente
$Acronimo = $ClusterConfig.Acronimo
$ClusterName = "$($Acronimo)_$($Ambiente)"
$ClusterCentral = Split-ConfigLine -ConfigLine $ClusterConfig.ClusterCentral
$ClusterRim = Split-ConfigLine -ConfigLine $ClusterConfig.ClusterRim
$ClusterAll = (,$ClusterCentral + $ClusterRim) | Where-Object { $_ } # rimuovi elementi nulli, se ce ne sono (es. no rim)
$InstallationType = $ClusterConfig.Installazione
# Ogni installazione ha alcuni servizi che devono restare su per poter eseguire il backup
if ($InstallationType -eq "Qlik Sense") {
    $ExcludedService = "QlikSenseRepositoryDatabase"
} elseif ($InstallationType -eq "NPrinting") {
    $ExcludedService = @("QlikNPrintingRepoService", "QlikNPrintingMessagingService")
    $ClusterName += "_$InstallationType"
}

# File di log e backup.
$Date = Get-Date -UFormat "%Y_%m_%d__%H_%M_%S"
if ($ManualBackup) {
    $BackupRoot = Get-FolderByFolderDialog
} else {
    $BackupRoot = $SystemConfig.BackupRoot
}
$BackupPath = "$BackupRoot\$ClusterName"
if (-not (Test-Path $BackupPath)) { New-Item -Path $BackupPath -ItemType Directory | Out-Null }
$LogPath = "$BackupRoot\$ClusterName\Logs"
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory | Out-Null }
$BackupLog = "$LogPath\$ClusterName-Backup_$Date.log"
$BackupToolLog = "$LogPath\$ClusterName-BackupTool_$Date.log"
$Sonda = "$InstallPath\Logs\$ClusterName-Sonda.log"
$BackupFile = "$BackupPath\$ClusterName-Backup_$Date.tar"
if ($InstallationType -eq "Qlik Sense") {
    $DumpAllFile = "$BackupPath\$ClusterName-DumpAll_$Date.dump"
    # La versione di PostgreSQL può cambiare in base all'installazione, per questo bisogna usare il carattere jolly.
    $BasePostgreSQLPath = "\Program Files\Qlik\Sense\Repository\PostgreSQL"
    if (Test-Path -Path C:$BasePostgreSQLPath) {
        $PostgreSQLPath = @(Join-Path -Path (Resolve-Path -Path C:$BasePostgreSQLPath\*) -ChildPath "bin" | Where-Object { Test-Path $_\pg_dump.exe })[0]
    } elseif (Test-Path -Path E:$BasePostgreSQLPath) {
        $PostgreSQLPath = @(Join-Path -Path (Resolve-Path -Path E:$BasePostgreSQLPath\*) -ChildPath "bin" | Where-Object { Test-Path $_\pg_dump.exe })[0]
    } else {
        if ($ClusterConfig.PercorsoPostgreSQL -and (Test-Path -Path $ClusterConfig.PercorsoPostgreSQL)) {
            $PostgreSQLPath = $ClusterConfig.PercorsoPostgreSQL
        } else {
            "-> ! Errore: Binari di PostgreSQL non trovati né in 'C:$BasePostgreSQLPath' né in 'E:$BasePostgreSQLPath'." | Out-File -FilePath $BackupLog
            "! Backup $Acronimo$Ambiente fallito!" | Out-File -FilePath $Sonda
            exit
        }
    }
} elseif ($InstallationType -eq "NPrinting") {
    $NPManagerPath = "C:\Program Files\NPrintingServer"
    if (-not (Test-Path -Path $NPManagerPath)) {
        "-> ! Errore: Binari di NPrinting Manager non trovati in '$NPManagerPath'." | Out-File -FilePath $BackupLog
        "! Backup $Acronimo$Ambiente fallito!" | Out-File -FilePath $Sonda
        exit
    }
}
# In alcuni cluster potrebbe usarsi una password diversa.
$RepositoryUser = $SystemConfig.RepositoryUser
if ($ClusterConfig.RepositoryPassword) {
    $RepositoryPassword = $ClusterConfig.RepositoryPassword
} else {
    $RepositoryPassword = $SystemConfig.RepositoryPassword
}

# Trascrivi l'output della console in un file di traccia.
Start-Transcript -Path $BackupLog -IncludeInvocationHeader

Write-Output "# Inizio procedura backup sul cluster $ClusterName."

### Arresto servizi ###

# Arresta tutti i servizi, prima sui rim e poi sui central (a meno che non si voglia eseguire solo il backup).
if (-not $ManualBackup) {
    $ClusterRim | Stop-QlikService

    $ClusterCentral | Stop-QlikService -Exclude $ExcludedService
}

### Esecuzione backup ###

Write-Output "`r`n# Esecuzione backup"

if ($InstallationType -eq "Qlik Sense") {
    # Salva la password in un file locale per l'accesso al database.
    $PGPass = "$env:USERPROFILE\AppData\Roaming\postgresql"
    if (-not (Test-Path -Path $PGPass)) {
        New-Item -ItemType Directory -Path $PGPass | Out-Null
    }
    "localhost:4432:*:$($RepositoryUser):$($RepositoryPassword)" | Set-Content $PGPass\pgpass.conf -Encoding Ascii
}

$BackupSuccess = $false
$BackupStart = Get-Date
Write-Output ("Inizio backup: {0}" -f $BackupStart.ToString("yyyy-MM-dd HH:mm:ss"))

if ($InstallationType -eq "Qlik Sense") {
    # Esegui il backup del Repository Database (dump).
    # Inoltre, salva l'output generato dal comando in un file di log.
    try {
        & "$PostgreSQLPath\pg_dump.exe" --host localhost --port 4432 --username postgres --no-password --format tar --blobs --verbose --file $BackupFile QSR 2>&1 | ForEach-Object {$_.ToString()} | Out-File $BackupToolLog
    } catch {
        Write-Output "Errore di 'pg_dump.exe'"
        Write-Output $_
    }
} elseif ($InstallationType -eq "NPrinting") {
    # Esegui il backup tramite NPrinting Manager.
    # Inoltre, salva l'output generato dal comando in un file di log.
    try {
        & "$NPManagerPath\Tools\Manager\Qlik.Nprinting.Manager.exe" backup -f $BackupFile -p "$NPManagerPath\pgsql\bin" --pg-password $RepositoryPassword 2>&1 | ForEach-Object {$_.ToString()} | Out-File $BackupToolLog
    } catch {
        Write-Output "Errore di 'Qlik.Nprinting.Manager.exe'"
        Write-Output $_
    }
}

$BackupEnd = Get-Date
$BackupElapsed = New-TimeSpan -Start $BackupStart -End $BackupEnd
Write-Output ("Fine backup: {0}" -f $BackupStart.ToString("yyyy-MM-dd HH:mm:ss"))
Write-Output ("(Tempo impiegato: {0} minuti {1} secondi)" -f [int] $BackupElapsed.TotalMinutes, $BackupElapsed.Seconds)

if ($InstallationType -eq "Qlik Sense") {
    # Se l'exit code è 0, il backup ha finito l'esecuzione senza errori.
    if ($LASTEXITCODE -eq 0) {
        $DumpAllStart = Get-Date
        Write-Output ("Inizio dumpall: {0}" -f $DumpAllStart.ToString("yyyy-MM-dd HH:mm:ss"))

        # Esegui il backuop dell'interno database (dumpall).
        try {
            & "$PostgreSQLPath\pg_dumpall.exe" --host localhost --port 4432 --username postgres > $DumpAllFile
        } catch {
            Write-Output "Errore di 'pg_dumpall.exe'"
            Write-Output $_
        }

        $DumpAllEnd = Get-Date
        $DumpAllElapsed = New-TimeSpan -Start $DumpAllStart -End $DumpAllEnd
        Write-Output ("Fine dumpall: {0}" -f $DumpAllEnd.ToString("yyyy-MM-dd HH:mm:ss"))
        Write-Output ("(Tempo impiegato: {0} minuti {1} secondi)" -f [int]$DumpAllElapsed.TotalMinutes, $DumpAllElapsed.Seconds)

        # Se entrambi gli exit code sono 0, sia il dump che il dumpall sono stati eseguiti senza errori.
        $BackupSuccess = ($LASTEXITCODE -eq 0)
    }
} elseif ($InstallationType -eq "NPrinting") {
    # Se l'exit code è 0, il backup è stato eseguito senza errori.
    $BackupSuccess = ($LASTEXITCODE -eq 0)
}

# Il backup è stato effettuato con successo se si verificano tre condizioni:
# * I backup sono stati eseguiti senza errori.
# * Esiste il file di backup.
# * Il file di backup non è vuoto.
if (($BackupSuccess) -and (Test-Path $BackupFile) -and ((Get-Item $BackupFile).Length -gt 0)) {
    Write-Output "-> Backup effettuato con successo."
    Write-Output ("Dimensione file di backup (dump): {0:N2} MB." -f ((Get-Item $BackupFile).Length / 1MB))
    if ($InstallationType -eq "Qlik Sense") {
        Write-Output ("Dimensione file di backup (dumpall): {0:N2} MB." -f ((Get-Item $DumpAllFile).Length / 1MB))
    }
    "$Date - Backup $ClusterName effettuato con successo." | Out-File -FilePath $Sonda
} else {
    Write-Output "-> ! Backup fallito."
    "! Backup $Acronimo$Ambiente fallito!" | Out-File -FilePath $Sonda
}

if ($ManualBackup) {
    # Se si vuole eseguire il solo backup, termina lo script in questo punto.
    Stop-Transcript
    exit
}

### Stop servizi esclusi dopo il backup ###

$ClusterCentral | Stop-QlikService -Services $ExcludedService

Start-Sleep -Seconds 1

### Avvio servizi ###

# Avvia tutti i servizi, prima sui central e poi sui rim.
$ClusterCentral | Start-QlikService

$ClusterRim | Start-QlikService

### Controllo raggiungibilità e tentativo riavvio servizi ###

# Controlla la raggiungibilità di Qlik Sense o NPrinting.
Write-Output "`r`nIn attesa avvio $InstallationType per controllo raggiungibilità..."
Start-Sleep -Seconds 60

if ($InstallationType -eq "Qlik Sense") {
    $RestartCluster = $false
    $RimsToRestart = @()
    $CheckAgain = $false
    foreach ($Node in $ClusterCentral) {
        $TestQlikSense = Test-QlikSenseAccess -ComputerName $Node
        Write-Output "Central $($Node): $(if (-not $TestQlikSense) {"NON "})raggiungibile."
        if (-not $TestQlikSense) {
            $RestartCluster = $true
            $CheckAgain = $true
        }
    }
    foreach ($Node in $ClusterRim) {
        $TestQlikSense = Test-QlikSenseAccess -ComputerName $Node
        Write-Output "Rim $($Node): $(if (-not $TestQlikSense) {"NON "})raggiungibile."
        if ((-not $TestQlikSense) -and (-not $RestartCluster)) {
            # Se non è necessario riavviare l'intero cluster, riavvia i singoli nodi non funzionanti.
            $RimsToRestart += $Node
            $CheckAgain = $true
        }
    }
} elseif ($InstallationType -eq "NPrinting") {
    $TestNPrinting = Test-NPrintingAccess -ComputerName (Get-NodeName)
    Write-Output "Console NPrinting: $(if (-not $TestNPrinting) {"NON "})raggiungibile."
    if (-not $TestNPrinting) {
        $RestartCluster = $true
        $CheckAgain = $true
    }
}

# Se Qlik Sense o NPrinting non sono raggiungibili, ritenta un riavvio dei servizi.
if ($RestartCluster) {
    # Riavvia l'intero cluster.
    Write-Output "`n-> ! Qlik Sense non è raggiungibile, nuovo tentativo di riavvio dei server."

    # Arresta tutti i servizi, prima sui rim e poi sui central.
    $ClusterRim | Stop-QlikService

    $ClusterCentral | Stop-QlikService

    # Avvia tutti i servizi, prima sui central e poi sui rim.
    $ClusterCentral | Start-QlikService

    $ClusterRim | Start-QlikService
} elseif ($RimsToRestart.count -gt 0) {
    # Riavvia solo i rim non raggiungibili.
    $RimsToRestart | Stop-QlikService

    $RimsToRestart | Start-QlikService
}

if ($CheckAgain) {
    Write-Output "`r`nIn attesa avvio $InstallationType per controllo raggiungibilità..."
    Start-Sleep -Seconds 120
    if ($InstallationType -eq "Qlik Sense") {
        foreach ($Node in $ClusterCentral) {
            $TestQlikSense = Test-QlikSenseAccess -ComputerName $Node
            Write-Output "Central $($Node): $(if (-not $TestQlikSense) {"NON "})raggiungibile."
        }
        foreach ($Node in $ClusterRim) {
            $TestQlikSense = Test-QlikSenseAccess -ComputerName $Node
            Write-Output "Rim $($Node): $(if (-not $TestQlikSense) {"NON "})raggiungibile."
        }
    } elseif ($InstallationType -eq "NPrinting") {
        $TestNPrinting = Test-NPrintingAccess -ComputerName (Get-NodeName)
        Write-Output "Console NPrinting: $(if (-not $TestNPrinting) {"NON "})raggiungibile."
    }
}

Stop-Transcript

if ((Get-Content $BackupLog) -contains "! Errore nell'arresto del servizio.") {
    Add-Content $Sonda -Value "! Servizi incartati!"
}