$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

$DropPath = "\\sede.corp.sanpaoloimi.com\app3prd\Qlik\Software\Rif_Bck"
$ClusterNodes = Import-Csv $ScriptPath\..\Data\NodiCluster.csv -Delimiter ';'

$StatusReport = @()
foreach ($Node in $ClusterNodes) {
    $Status = . $ScriptPath\Start-StatusJob.ps1 -Type "Status" -Ambiente $Node.Ambiente -Acronimo $Node.Acronimo -Installazione $Node.Installazione -Hostname $Node.Hostname -TipoNodo $Node.TipoNodo
    $BackupStatus = . $ScriptPath\Start-StatusJob.ps1 -Type "BackupStatus" -Ambiente $Node.Ambiente -Acronimo $Node.Acronimo -Installazione $Node.Installazione
    $BackupStatusReadable = if (-not $BackupStatus) {
        "Non attivato"
    } elseif ($BackupStatus -like "*fallito*") { 
        "Fallito"
    } elseif (-not ($BackupStatus -like "*$((Get-Date).AddDays(-1).ToString("yyy_MM_dd"))*")) {
        "Non effettuato"
    } elseif ($BackupStatus -like "*successo*") {
        "Successo"
    } else {
        $BackupStatus
    }
    if ($BackupStatus -like "*incartati*") {
        $BackupStatusReadable += ", servizi incartati"
    }
    $StatusReport += [PSCustomObject]@{
        Acronimo = $Node.Acronimo
        Ambiente = $Node.Ambiente
        Hostname = $Node.Hostname
        Installazione = $Node.Installazione
        TipoNodo = $Node.TipoNodo
        Stato = $Status
        StatoBackup = $BackupStatusReadable
    }
}

$StatusReport | ConvertTo-Csv -Delimiter ";" -NoTypeInformation | Out-File -FilePath $DropPath\StatusReport.csv