<#

.SINOSSI

    Interfaccia grafica per la gestione delle installazioni Qlik Butler.

.DESCRIZIONE

    Lo script crea un'interfaccia grafica che richiama le funzionalità di QlikButlerManager in modo più intuitivo.

.NOTE

    Autore: Matteo Silvestro
    Versione: 3.0.6
    Ultimo aggiornamento: 25/11/2019

#>

$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

Import-Module $ScriptPath\Data\QlikButlerManagerToolbox.psm1

# Variabili di base per il layout.
$Margin = 10
$Width = 798
$StatusGridViewHeight = 400
$ButtonWidth = 192
$ButtonHeight = 50
$ProgressBarHeight = 30
$LabelHeight = 15

$MarginTop = $Margin
$MarginLeft = $Margin

$ClusterNodes = Import-Csv $ScriptPath\Data\NodiCluster.csv -Delimiter ';'
$Clusters = $ClusterNodes | Select-Object -Unique -Property Acronimo, Ambiente, Installazione

$Commands = Get-Content $ScriptPath\Data\Commands.json | ConvertFrom-Json

$InitializeStatusGridView = {
    foreach ($Node in $ClusterNodes) {
        [void] $StatusGridView.Rows.Add($Node.Acronimo, $Node.Ambiente, $Node.Hostname, $Node.Installazione, $Node.TipoNodo)
    }
    foreach ($Column in $StatusGridView.Columns) {
        $Column.AutoSizeMode = "AllCells"
    }    
}

$StartStatusJobs = {

    $StatusButton.Enabled = $false

    if ($StatusGridView.Columns["Stato"]) {
        $StatusGridView.Columns.Remove("Stato")
    }
    $Ind = $StatusGridView.Columns.Add("Stato", "Stato")
    $StatusGridView.Columns[$Ind].AutoSizeMode = "AllCells"

    $script:StatusProgressValue = 0
    $script:StatusMaxProgressValue = $ClusterNodes.Count
    $StatusProgressBar.Value = 0

    foreach ($Node in $ClusterNodes) {
        Start-Job -Name "StatusJobStatus$Node" -ScriptBlock {
            param(
                [string] $ScriptPath,
                [string] $Ambiente,
                [string] $Acronimo,
                [string] $Installazione,
                [string] $Hostname,
                [string] $TipoNodo
            )

            . $ScriptPath\Data\Start-StatusJob.ps1 -Type "Status" -Ambiente $Ambiente -Acronimo $Acronimo -Installazione $Installazione -Hostname $Hostname -TipoNodo $TipoNodo
        } -ArgumentList $ScriptPath, $Node.Ambiente, $Node.Acronimo, $Node.Installazione, $Node.Hostname, $Node.TipoNodo | Out-Null
    }
    
    $StatusLabel.Text = "Aggiornamento stato in corso"

    $StatusTimer.Start()
}

$ReceiveStatusJobs = {
    foreach ($Node in $ClusterNodes) {
        $StatusJob = Get-Job -Name "StatusJobStatus$Node"
        if (($StatusJob.HasMoreData) -and ($StatusJob.State -eq "Completed")) {
            $Status = $StatusJob | Receive-Job
            foreach ($Row in $StatusGridView.Rows) {
                if (($Row.Cells["Hostname"].Value -eq $Node.Hostname)) {
                    $Row.Cells["Stato"].Value = $Status
                    $Row.Cells["Stato"].Style.ForeColor = if ($Status -eq "Raggiungibile") { "Green" } else { "Red" }
                }
            }
            $script:StatusProgressValue += 1
        }
    }
    $Label = $StatusLabel.Text
    if ($Label.Substring($Label.Length - 3) -eq "...") {
        $StatusLabel.Text = $Label.Substring(0, $Label.Length - 3)
    } else {
        $StatusLabel.Text = $Label + "."
    }
    $StatusProgressBar.Value = ($script:StatusProgressValue / $script:StatusMaxProgressValue) * 100
    if (-not ((Get-Job -Name "StatusJobStatus*").HasMoreData -eq $true)) {
        $StatusLabel.Text = "Ultimo aggiornamento alle $(Get-Date -UFormat "%H:%M:%S")"
        Get-Job -Name "StatusJobStatus*" | Remove-Job
        $StatusButton.Enabled = $true
        $StatusTimer.Stop()
    }
}

$StartVersionJobs = {

    $VersionButton.Enabled = $false

    if ($StatusGridView.Columns["Versione"]) {
        $StatusGridView.Columns.Remove("Versione")
    }
    $Ind = $StatusGridView.Columns.Add("Versione", "Versione")
    $StatusGridView.Columns[$Ind].AutoSizeMode = "AllCells"
    if ($StatusGridView.Columns["Schedulazioni"]) {
        $StatusGridView.Columns.Remove("Schedulazioni") 
    }
    $Ind = $StatusGridView.Columns.Add("Schedulazioni", "Schedulazioni")
    $StatusGridView.Columns[$Ind].AutoSizeMode = "AllCells"

    $script:VersionProgressValue = 0
    $script:VersionMaxProgressValue = $Clusters.Count
    $VersionProgressBar.Value = 0

    foreach ($Cluster in $Clusters) {
        Start-Job -Name "StatusJobVersion$Cluster" -ScriptBlock {
            param(
                [string] $ScriptPath,
                [string] $Ambiente,
                [string] $Acronimo,
                [string] $Installazione
            )

            . $ScriptPath\Data\Start-StatusJob.ps1 -Type "Version" -Ambiente $Ambiente -Acronimo $Acronimo -Installazione $Installazione
        } -ArgumentList $ScriptPath, $Cluster.Ambiente, $Cluster.Acronimo, $Cluster.Installazione | Out-Null
    }

    $VersionLabel.Text = "Aggiornamento versione in corso"

    $VersionTimer.Start()
}

$ReceiveVersionJobs = {
    foreach ($Cluster in $Clusters) {
        $VersionJob = Get-Job -Name "StatusJobVersion$Cluster"
        if (($VersionJob.HasMoreData) -and ($VersionJob.State -eq "Completed")) {
            $Version, $Tasks = $VersionJob | Receive-Job
            if (-not $Version) {
                $Version = "X"
            }
            foreach ($Row in $StatusGridView.Rows) {
                if (($Row.Cells["Acronimo"].Value -eq $Cluster.Acronimo) -and ($Row.Cells["Ambiente"].Value -eq $Cluster.Ambiente) -and ($Row.Cells["Installazione"].Value -eq $Cluster.Installazione)) {
                    $Row.Cells["Versione"].Value = if ($Version) { $Version } else { "X" }
                    $Row.Cells["Schedulazioni"].Value = if ($Tasks) { "Installate" } else { "Non installate" }
                }
            }
            $script:VersionProgressValue += 1
        }
    }
    $Label = $VersionLabel.Text
    if ($Label.Substring($Label.Length - 3) -eq "...") {
        $VersionLabel.Text = $Label.Substring(0, $Label.Length - 3)
    } else {
        $VersionLabel.Text = $Label + "."
    }
    $VersionProgressBar.Value = ($script:VersionProgressValue / $script:VersionMaxProgressValue) * 100
    if (-not ((Get-Job -Name "StatusJobVersion*").HasMoreData -eq $true)) {
        $VersionLabel.Text = "Ultimo aggiornamento alle $(Get-Date -UFormat "%H:%M:%S")"
        Get-Job -Name "StatusJobVersion*" | Remove-Job
        $VersionButton.Enabled = $true
        $VersionTimer.Stop()
    }
}

$StartBackupStatusJobs = {

    $BackupStatusButton.Enabled = $false

    if ($StatusGridView.Columns["StatoBackup"]) {
        $StatusGridView.Columns.Remove("StatoBackup")
    }
    $Ind = $StatusGridView.Columns.Add("StatoBackup", "Stato backup")
    $StatusGridView.Columns[$Ind].AutoSizeMode = "AllCells"

    $script:BackupStatusProgressValue = 0
    $script:BackupStatusMaxProgressValue = $Clusters.Count
    $BackupStatusProgressBar.Value = 0

    foreach ($Cluster in $Clusters) {
        Start-Job -Name "StatusJobBackupStatus$Cluster" -ScriptBlock {
            param(
                [string] $ScriptPath,
                [string] $Ambiente,
                [string] $Acronimo,
                [string] $Installazione
            )

            . $ScriptPath\Data\Start-StatusJob.ps1 -Type "BackupStatus" -Ambiente $Ambiente -Acronimo $Acronimo -Installazione $Installazione
        } -ArgumentList $ScriptPath, $Cluster.Ambiente, $Cluster.Acronimo, $Cluster.Installazione | Out-Null
    }

    $BackupStatusLabel.Text = "Aggiornamento stato b. in corso"

    $BackupStatusTimer.Start()
}

$ReceiveBackupStatusJobs = {
    foreach ($Cluster in $Clusters) {
        $BackupStatusJob = Get-Job -Name "StatusJobBackupStatus$Cluster"
        if (($BackupStatusJob.HasMoreData) -and ($BackupStatusJob.State -eq "Completed")) {
            $BackupStatus = $BackupStatusJob | Receive-Job
            foreach ($Row in $StatusGridView.Rows) {
                if (($Row.Cells["Acronimo"].Value -eq $Cluster.Acronimo) -and ($Row.Cells["Ambiente"].Value -eq $Cluster.Ambiente) -and ($Row.Cells["Installazione"].Value -eq $Cluster.Installazione)) {
                    $Row.Cells["StatoBackup"].Value = if (-not $BackupStatus) {
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
                    $Row.Cells["StatoBackup"].Style.ForeColor = switch ($Row.Cells["StatoBackup"].Value) {
                       "Successo" { "Green"; break }
                       "Fallito" { "Red"; break }
                       "Non attivato" { "DarkOrange"; break }
                       "Non effettuato" { "DarkOrange"; break }
                    }
                    if ($BackupStatus -like "*incartati*") {
                        $Row.Cells["StatoBackup"].Value += ", servizi incartati"
                        $Row.Cells["StatoBackup"].Style.BackColor = "Khaki"
                    }
                }
            }
            $script:BackupStatusProgressValue += 1
        }
    }
    $Label = $BackupStatusLabel.Text
    if ($Label.Substring($Label.Length - 3) -eq "...") {
        $BackupStatusLabel.Text = $Label.Substring(0, $Label.Length - 3)
    } else {
        $BackupStatusLabel.Text = $Label + "."
    }
    $BackupStatusProgressBar.Value = ($script:BackupStatusProgressValue / $script:BackupStatusMaxProgressValue) * 100
    if (-not ((Get-Job -Name "StatusJobBackupStatus*").HasMoreData -eq $true)) {
        $BackupStatusLabel.Text = "Ultimo aggiornamento alle $(Get-Date -UFormat "%H:%M:%S")"
        Get-Job -Name "StatusJobBackupStatus*" | Remove-Job
        $BackupStatusButton.Enabled = $true
        $BackupStatusTimer.Stop()
    }
}

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$Form = New-Object System.Windows.Forms.Form
$Form.Padding = $Margin
$Form.AutoSize = $true
$Version = Get-Content -Path $ScriptPath\Data\Version.txt
$Form.Text = "Qlik Butler Manager v$Version"
$Form.TopMost = $false
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "Fixed3D" # non si può ridimensionare
$Form.Icon = "$ScriptPath\QlikButlerManager.ico"

## Visualizzazione stato cluster  ##

$StatusGridView = New-Object System.Windows.Forms.DataGridView
$StatusGridView.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$StatusGridView.Width = $Width
$StatusGridView.Height = $StatusGridViewHeight
$StatusGridView.Name = "StatusGridView"
$StatusGridView.ReadOnly = $true
$StatusGridView.AllowUserToAddRows = $false
$StatusGridView.SelectionMode = "FullRowSelect"
$StatusGridView.ColumnHeadersVisible = $true
$StatusGridView.RowHeadersVisible = $false
$StatusGridView.AllowUserToResizeRows = $false
[void] $StatusGridView.Columns.Add("Acronimo", "Acronimo")
[void] $StatusGridView.Columns.Add("Ambiente", "Ambiente")
[void] $StatusGridView.Columns.Add("Hostname", "Hostname")
[void] $StatusGridView.Columns.Add("Installazione", "Installazione")
[void] $StatusGridView.Columns.Add("TipoNodo", "Tipo nodo")

$Form.Controls.Add($StatusGridView)

## Colonna dello stato ##

$MarginTop = $Margin + $StatusGridViewHeight + $Margin
$MarginLeft = $Margin

$StatusButton = New-Object System.Windows.Forms.Button
$StatusButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$StatusButton.Size = New-Object System.Drawing.Size($ButtonWidth, $ButtonHeight)
$StatusButton.Text = "Ottieni stato"
$StatusButton.Enabled = $true
$StatusButton.Add_Click({
    & $StartStatusJobs
})

$MarginTop += $ButtonHeight + $Margin

$StatusProgressBar = New-Object System.Windows.Forms.ProgressBar
$StatusProgressBar.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$StatusProgressBar.Size = New-Object System.Drawing.Size($ButtonWidth, $ProgressBarHeight)
$StatusProgressBar.Value = 0
$StatusProgressBar.Style = "Continuous"

$MarginTop += $ProgressBarHeight + $Margin

$StatusLabel = New-Object System.Windows.Forms.Label
$StatusLabel.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$StatusLabel.Size = New-Object System.Drawing.Size($ButtonWidth, $LabelHeight)
$StatusLabel.Text = "Stato non aggiornato."

$Form.Controls.AddRange(($StatusProgressBar, $StatusButton, $StatusLabel))

## Colonna dello stato dei backup ##

$MarginTop = $Margin + $StatusGridViewHeight + $Margin
$MarginLeft += $ButtonWidth + $Margin

$BackupStatusButton = New-Object System.Windows.Forms.Button
$BackupStatusButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$BackupStatusButton.Size = New-Object System.Drawing.Size($ButtonWidth, $ButtonHeight)
$BackupStatusButton.Text = "Ottieni stato backup"
$BackupStatusButton.Enabled = $true
$BackupStatusButton.Add_Click({
    & $StartBackupStatusJobs
})

$MarginTop += $ButtonHeight + $Margin

$BackupStatusProgressBar = New-Object System.Windows.Forms.ProgressBar
$BackupStatusProgressBar.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$BackupStatusProgressBar.Size = New-Object System.Drawing.Size($ButtonWidth, $ProgressBarHeight)
$BackupStatusProgressBar.Value = 0
$BackupStatusProgressBar.Style = "Continuous"

$MarginTop += $ProgressBarHeight + $Margin

$BackupStatusLabel = New-Object System.Windows.Forms.Label
$BackupStatusLabel.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$BackupStatusLabel.Size = New-Object System.Drawing.Size($ButtonWidth, $LabelHeight)
$BackupStatusLabel.Text = "Stato backup non aggiornato."

$Form.Controls.AddRange(($BackupStatusProgressBar, $BackupStatusButton, $BackupStatusLabel))

## Colonna della versione ##

$MarginTop = $Margin + $StatusGridViewHeight + $Margin
$MarginLeft += $ButtonWidth + $Margin

$VersionButton = New-Object System.Windows.Forms.Button
$VersionButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$VersionButton.Size = New-Object System.Drawing.Size($ButtonWidth, $ButtonHeight)
$VersionButton.Text = "Ottieni versione"
$VersionButton.Enabled = $true
$VersionButton.Add_Click({
    & $StartVersionJobs
})

$MarginTop += $ButtonHeight + $Margin

$VersionProgressBar = New-Object System.Windows.Forms.ProgressBar
$VersionProgressBar.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$VersionProgressBar.Size = New-Object System.Drawing.Size($ButtonWidth, $ProgressBarHeight)
$VersionProgressBar.Value = 0
$VersionProgressBar.Style = "Continuous"

$MarginTop += $ProgressBarHeight + $Margin

$VersionLabel = New-Object System.Windows.Forms.Label
$VersionLabel.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$VersionLabel.Size = New-Object System.Drawing.Size($ButtonWidth, $LabelHeight)
$VersionLabel.Text = "Versione non aggiornata."

$Form.Controls.AddRange(($VersionButton, $VersionProgressBar, $VersionLabel))

## Colonna dei comandi ##

$MarginTop = $Margin + $StatusGridViewHeight + $Margin
$MarginLeft += $ButtonWidth + $Margin

$CommandComboBox = New-Object System.Windows.Forms.ComboBox
$CommandComboBox.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$CommandComboBox.Width = $ButtonWidth
$CommandComboBox.Text = "Operazione"
$CommandComboBox.DropDownStyle = "DropDownList"
$CommandComboBox.DataSource = $Commands | foreach { $_.Name }

$MarginTop += 20 + $Margin

$CommandButton = New-Object System.Windows.Forms.Button
$CommandButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$CommandButton.Size = New-Object System.Drawing.Size($ButtonWidth, $ButtonHeight)
$CommandButton.Text = "Esegui operazione sui cluster"
$CommandButton.Enabled = $true
$CommandButton.Add_Click({
    $SelectedCommand = $Commands | where { $_.Name -eq $CommandComboBox.SelectedValue }
    $CommandScript = $SelectedCommand.CommandScript
    $Type = $SelectedCommand.Type
    $Params = $SelectedCommand.Params
    $Params | ConvertTo-Json | Out-File $ScriptPath\Data\Params.json

    if ($Type -eq "Cluster") {
        $Clusters = @()
        foreach ($Row in $StatusGridView.SelectedRows) {
            $Clusters += @([pscustomobject] @{
                Acronimo = $Row.Cells["Acronimo"].Value;
                Ambiente = $Row.Cells["Ambiente"].Value;
                Installazione = $Row.Cells["Installazione"].Value
            })
        }
        $Clusters = $Clusters | Select-Object -Property Acronimo, Ambiente, Installazione -Unique
        $Clusters | Export-Csv $ScriptPath\Data\SelectedClusters.csv -NoTypeInformation -Delimiter ";"
        $ScriptToExecute = "-File `"$ScriptPath\Data\Start-ClusterJob.ps1`" -ClustersCsv `"$ScriptPath\Data\SelectedClusters.csv`" -CommandScript `"$CommandScript`" -ParamsJson `"$ScriptPath\Data\Params.json`""
    } elseif ($Type -eq "Node") {
        $Nodes = @()
        foreach ($Row in $StatusGridView.SelectedRows) {
            $Nodes += @([pscustomobject] @{
                Hostname = $Row.Cells["Hostname"].Value;
            })
        }
        $Nodes | Export-Csv $ScriptPath\Data\SelectedNodes.csv -NoTypeInformation -Delimiter ";"
        $ScriptToExecute = "-File `"$ScriptPath\Data\Start-NodeJob.ps1`" -NodesCsv `"$ScriptPath\Data\SelectedNodes.csv`" -CommandScript `"$CommandScript`" -ParamsJson `"$ScriptPath\Data\Params.json`""
    }
    Start-Process PowerShell -ArgumentList $ScriptToExecute -Wait
})

$Form.Controls.AddRange(($CommandComboBox, $CommandButton))

$StatusTimer = New-Object System.Windows.Forms.Timer
$StatusTimer.Interval = 500
$StatusTimer.Add_Tick($ReceiveStatusJobs)
$StatusTimer.Enabled = $false

$VersionTimer = New-Object System.Windows.Forms.Timer
$VersionTimer.Interval = 1000
$VersionTimer.Add_Tick($ReceiveVersionJobs)

$BackupStatusTimer = New-Object System.Windows.Forms.Timer
$BackupStatusTimer.Interval = 1000
$BackupStatusTimer.Add_Tick($ReceiveBackupStatusJobs)

& $InitializeStatusGridView
Get-Job -Name "StatusJob*" | Remove-Job -Force

[void] $Form.ShowDialog()