<#

.SINOSSI

    Script per la generazione dell'interfaccia graficia di Qlik Butler.

.DESCRIZIONE

    Lo script crea un elenco di pulsanti che eseguono gli script di Qlik Butler.

.NOTE

    Autori: Matteo Silvestro (Consoft S.p.A.)
    Versione: 3.0.6
    Ultimo aggiornamento: 27/01/2020

#>

param(
    [switch] $QlikSenseCluster = $false,
    [switch] $NPrintingCluster = $false
)

# Variabili di base per il layout.
$ServicesGroupWidth = 300    # lunghezza del gruppo a sinistra per i servizi
$CommandsGroupWidth = 200    # lunghezza del gruppo a destra per i comandi
$Margin = 10                 # margine tra elementi di un gruppo
$MarginGroupBox = 14         # margine interno dei gruppi
$ButtonHeight = 50           # altezza dei pulsanti
$ServicesButtonWidth = 84    # lunghezza dei pulsanti per la gestione dei servizi
$CommandsButtonWidth = 172   # lunghezza dei pulsanti per l'esecuzione dei comandi
$ServicesTextBoxHeight = 150 # altezza dell'area di testo che mostra lo stato dei servizi
$AvailableCommands = @("Imposta tutti i servizi in manual", "Imposta tutti i servizi in automatic", "Avvia solo Qlik Sense Repository Database", "Arresta e disabilita servizi superflui", "Installa Qlik Cli")

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

# Importa le funzioni ausiliari per l'avvio e l'arresto dei servizi.
Import-Module $InstallPath\QlikButler\Data\QlikButlerToolbox.psm1

# Carica il file di configurazione.
$ClusterConfig = Import-ConfigFile -ConfigFile $InstallPath\QlikButler\Data\Cluster.config

$Version = Get-Content -Path $InstallPath\QlikButler\Data\Version.txt

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$Form = New-Object System.Windows.Forms.Form
$Form.Padding = $Margin
$Form.AutoSize = $true
$Form.Text = "Qlik Butler v$Version"
$Form.TopMost = $false
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "Fixed3D" # non si può ridimensionare
$Form.Icon = "$InstallPath\QlikButler\Data\QlikButler.ico"

function Start-PowerShellScript {
    param (
        [string] $ScriptFile,
        [string] $Arguments = ""
    )

    $ScriptToExecute = "-Command `". $InstallPath\QlikButler\$ScriptFile.ps1 $Arguments; Read-Host '`r`nPremere invio per chiudere'`""
    Start-Process powershell -ArgumentList $ScriptToExecute -Wait
}

function Update-ServicesDisplay {
    $NodeServicesListView.Items.Clear()
    $QlikServices = @()
    Get-QlikService | ForEach-Object { $QlikServices += (Get-Service -Include $_) }
    $QlikServices = $QlikServices | Select-Object DisplayName, Status, @{n = "StartMode"; e = {
        (Get-WmiObject -Class Win32_Service -Property StartMode -Filter "Name='$($_.Name)'").StartMode
    }}
    foreach ($Service in $QlikServices) {
        $ListViewItem = New-Object System.Windows.Forms.ListViewItem($Service.DisplayName)
	    $ListViewItem.SubItems.Add([string] $Service.Status) | Out-Null
        $ListViewItem.SubItems.Add($Service.StartMode) | Out-Null
        $ListViewItem.UseItemStyleForSubItems = $false
        $ServiceStatus = $ListViewItem.SubItems[1]
        if ($ServiceStatus.Text -eq "Running") {
            $ServiceStatus.ForeColor = "Green"
        } elseif ($ServiceStatus.Text -eq "Stopped") {
            $ServiceStatus.ForeColor = "Red"
        }
	    $NodeServicesListView.Items.AddRange(($ListViewItem))
    }
    [void] $NodeServicesListView.AutoResizeColumns(1)
}

# -- Gestione servizi per l'intero cluster --

$QlikSenseClusterServicesGroupBox = New-Object System.Windows.Forms.GroupBox
$QlikSenseClusterServicesGroupBox.Location = New-Object System.Drawing.Point($Margin, $Margin)
$QlikSenseClusterServicesGroupBox.Width = $ServicesGroupWidth
$QlikSenseClusterServicesGroupBox.Text = "Servizi cluster"

$MarginTop = 6 + $MarginGroupBox
$MarginLeft = $MarginGroupBox

$StopClusterServicesButton = New-Object System.Windows.Forms.Button
$StopClusterServicesButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$StopClusterServicesButton.Size = New-Object System.Drawing.Size($ServicesButtonWidth, $ButtonHeight)
$StopClusterServicesButton.Text = "☐`nArresta"
if ($QlikSenseCluster -or $NPrintingCluster) { $StopClusterServicesButton.BackColor = "Salmon" }
$StopClusterServicesButton.Enabled = ($QlikSenseCluster -or $NPrintingCluster)
$StopClusterServicesButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Restart-ClusterService" -Arguments " -OnlyStop"
    Update-ServicesDisplay
})

$MarginLeft += $ServicesButtonWidth + $Margin

$StartClusterServicesButton = New-Object System.Windows.Forms.Button
$StartClusterServicesButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$StartClusterServicesButton.Size = New-Object System.Drawing.Size($ServicesButtonWidth, $ButtonHeight)
$StartClusterServicesButton.Text = "▷`nAvvia"
if ($QlikSenseCluster -or $NPrintingCluster) { $StartClusterServicesButton.BackColor = "Salmon" }
$StartClusterServicesButton.Enabled = ($QlikSenseCluster -or $NPrintingCluster)
$StartClusterServicesButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Restart-ClusterService" -Arguments " -OnlyStart"
    Update-ServicesDisplay
})

$MarginLeft += $ServicesButtonWidth + $Margin

$RestartClusterServicesButton = New-Object System.Windows.Forms.Button
$RestartClusterServicesButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$RestartClusterServicesButton.Size = New-Object System.Drawing.Size($ServicesButtonWidth, $ButtonHeight)
$RestartClusterServicesButton.Text = "↻`nRiavvia"
if ($QlikSenseCluster -or $NPrintingCluster) { $RestartClusterServicesButton.BackColor = "Salmon" }
$RestartClusterServicesButton.Enabled = ($QlikSenseCluster -or $NPrintingCluster)
$RestartClusterServicesButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Restart-ClusterService"
    Update-ServicesDisplay
})

$MarginTop += $ButtonHeight
$MarginLeft += $ServicesButtonWidth + $Margin

$QlikSenseClusterServicesGroupBox.Height = $MarginTop + $MarginGroupBox
$QlikSenseClusterServicesGroupBox.Controls.AddRange(@($StopClusterServicesButton, $StartClusterServicesButton, $RestartClusterServicesButton))

# -- Gestione servizi per il singolo nodo --

$NodeServicesGroupBox = New-Object System.Windows.Forms.GroupBox
$NodeServicesGroupBoxY = $QlikSenseClusterServicesGroupBox.Height + 2*$Margin
$NodeServicesGroupBox.Location = New-Object System.Drawing.Point($Margin, $NodeServicesGroupBoxY)
$NodeServicesGroupBox.Width = $ServicesGroupWidth
$NodeServicesGroupBox.Text = "Servizi nodo"

$MarginTop = 6 + $MarginGroupBox
$MarginLeft = $MarginGroupBox

$NodeServicesListView = New-Object System.Windows.Forms.ListView
$NodeServicesListView.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$NodeServicesListView.Width = $ServicesGroupWidth - 2*$MarginLeft
$NodeServicesListView.Height = $ServicesTextBoxHeight
$NodeServicesListView.View = "Details"
$NodeServicesListView.Columns.Add("Nome servizio") | Out-Null
$NodeServicesListView.Columns.Add("Stato") | Out-Null
$NodeServicesListView.Columns.Add("Modalità") | Out-Null

$MarginTop += $ServicesTextBoxHeight + $Margin

$StopNodeServicesButton = New-Object System.Windows.Forms.Button
$StopNodeServicesButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$StopNodeServicesButton.Size = New-Object System.Drawing.Size($ServicesButtonWidth, $ButtonHeight)
$StopNodeServicesButton.Text = "☐`nArresta"
$StopNodeServicesButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Restart-NodeService" -Arguments " -OnlyStop"
    Update-ServicesDisplay
})

$MarginLeft += $ServicesButtonWidth + $Margin

$StartNodeServicesButton = New-Object System.Windows.Forms.Button
$StartNodeServicesButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$StartNodeServicesButton.Size = New-Object System.Drawing.Size($ServicesButtonWidth, $ButtonHeight)
$StartNodeServicesButton.Text = "▷`nAvvia"
$StartNodeServicesButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Restart-NodeService" -Arguments " -OnlyStart"
    Update-ServicesDisplay
})

$MarginLeft += $ServicesButtonWidth + $Margin

$RestartNodeServicesButton = New-Object System.Windows.Forms.Button
$RestartNodeServicesButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$RestartNodeServicesButton.Size = New-Object System.Drawing.Size($ServicesButtonWidth, $ButtonHeight)
$RestartNodeServicesButton.Text = "↻`nRiavvia"
$RestartNodeServicesButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Restart-NodeService"
    Update-ServicesDisplay
})

$MarginTop += $ButtonHeight + $Margin
$MarginLeft = $MarginGroupBox

$CommandComboBox = New-Object System.Windows.Forms.ComboBox
$CommandComboBox.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$CommandComboBox.Width = 2*$ServicesButtonWidth + $Margin
$CommandComboBox.Text = "Acronimo"
$CommandComboBox.DropDownStyle = "DropDownList"
$CommandComboBox.DataSource = $AvailableCommands

$MarginLeft += $CommandComboBox.Width + $Margin

$ExecuteCommandButton = New-Object System.Windows.Forms.Button
$ExecuteCommandButton.Location = New-Object System.Drawing.Point($MarginLeft, $MarginTop)
$ExecuteCommandButton.Size = New-Object System.Drawing.Size($ServicesButtonWidth, $CommandComboBox.Height)
$ExecuteCommandButton.Text = "Esegui"
$ExecuteCommandButton.Add_Click({
    if ($CommandComboBox.SelectedValue -eq "Avvia solo Qlik Sense Repository Database") {
        Start-PowerShellScript -ScriptFile "Restart-NodeService" -Arguments " -OnlyStart -Services 'QlikSenseRepositoryDatabase'"
    } else {
        Start-PowerShellScript -ScriptFile "Start-Commands" -Arguments " -Command '$($CommandComboBox.SelectedValue)'"
    }
    Update-ServicesDisplay
})

$MarginTop += $CommandComboBox.Height

$NodeServicesGroupBox.Height = $MarginTop + $MarginGroupBox
$NodeServicesGroupBox.Controls.AddRange(@($NodeServicesListView, $StopNodeServicesButton, $StartNodeServicesButton, $RestartNodeServicesButton, $CommandComboBox, $ExecuteCommandButton))

# -- Comandi intero cluster --

$QlikSenseClusterCommandsGroupBox = New-Object System.Windows.Forms.GroupBox
$QlikSenseClusterCommandsGroupBoxX = $ServicesGroupWidth + 2*$Margin
$QlikSenseClusterCommandsGroupBox.Location = New-Object System.Drawing.Point($QlikSenseClusterCommandsGroupBoxX, $Margin)
$QlikSenseClusterCommandsGroupBox.Width = $CommandsGroupWidth
$QlikSenseClusterCommandsGroupBox.Text = "Comandi cluster"

$MarginTop = 6 + $MarginGroupBox
$MarginLeft = $MarginGroupBox

$PublishAppButton = New-Object System.Windows.Forms.Button
$PublishAppButton.Location = New-Object System.Drawing.Point($MarginGroupBox, $MarginTop)
$PublishAppButton.Size = New-Object System.Drawing.Size($CommandsButtonWidth, $ButtonHeight)
$PublishAppButton.Text = "Importa e pubblica app"
$PublishAppButton.Enabled = $QlikSenseCluster
$PublishAppButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Import-App"
})

$MarginTop += $ButtonHeight + $Margin

$ImportSecurityRulesButton = New-Object System.Windows.Forms.Button
$ImportSecurityRulesButton.Location = New-Object System.Drawing.Point($MarginGroupBox, $MarginTop)
$ImportSecurityRulesButton.Size = New-Object System.Drawing.Size($CommandsButtonWidth, $ButtonHeight)
$ImportSecurityRulesButton.Text = "Esegui estrazione e importazione Security Rules"
$ImportSecurityRulesButton.Enabled = $QlikSenseCluster
$ImportSecurityRulesButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Import-SecurityRule"
})

$MarginTop += $ButtonHeight + $Margin

$ImportExtensionButton = New-Object System.Windows.Forms.Button
$ImportExtensionButton.Location = New-Object System.Drawing.Point($MarginGroupBox, $MarginTop)
$ImportExtensionButton.Size = New-Object System.Drawing.Size($CommandsButtonWidth, $ButtonHeight)
$ImportExtensionButton.Text = "Importa Extensions"
$ImportExtensionButton.Enabled = $QlikSenseCluster
$ImportExtensionButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Import-Extension"
})

$MarginTop += $ButtonHeight + $Margin

$ManualBackupButton = New-Object System.Windows.Forms.Button
$ManualBackupButton.Location = New-Object System.Drawing.Point($MarginGroupBox, $MarginTop)
$ManualBackupButton.Size = New-Object System.Drawing.Size($CommandsButtonWidth, $ButtonHeight)
$ManualBackupButton.Text = "Backup manuale"
$ManualBackupButton.Enabled = ($QlikSenseCluster -or $NPrintingCluster)
$ManualBackupButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Backup-Cluster" -Arguments " -ManualBackup"
})

$MarginTop += $ButtonHeight + $Margin

$CleanBackupFilesButton = New-Object System.Windows.Forms.Button
$CleanBackupFilesButton.Location = New-Object System.Drawing.Point($MarginGroupBox, $MarginTop)
$CleanBackupFilesButton.Size = New-Object System.Drawing.Size($CommandsButtonWidth, $ButtonHeight)
$CleanBackupFilesButton.Text = "Svecchiamento backup"
$CleanBackupFilesButton.Enabled = ($QlikSenseCluster -or $NPrintingCluster)
$CleanBackupFilesButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Clean-BackupFiles"
})

$MarginTop += $ButtonHeight + $Margin

$CleanUserPassesButton = New-Object System.Windows.Forms.Button
$CleanUserPassesButton.Location = New-Object System.Drawing.Point($MarginGroupBox, $MarginTop)
$CleanUserPassesButton.Size = New-Object System.Drawing.Size($CommandsButtonWidth, $ButtonHeight)
$CleanUserPassesButton.Text = "Svecchiamento licenze"
$CleanUserPassesButton.Enabled = $QlikSenseCluster
$CleanUserPassesButton.Add_Click({
    Start-PowerShellScript -ScriptFile "Clean-UserPasses"
})

$MarginTop += $ButtonHeight

$QlikSenseClusterCommandsGroupBox.Height = $MarginTop + $MarginGroupBox
$QlikSenseClusterCommandsGroupBox.Controls.AddRange(@($PublishAppButton, $ImportSecurityRulesButton, $ImportExtensionButton, $ManualBackupButton, $CleanBackupFilesButton, $CleanUserPassesButton))

$Form.Controls.AddRange(@($QlikSenseClusterServicesGroupBox, $NodeServicesGroupBox, $QlikSenseClusterCommandsGroupBox))

Update-ServicesDisplay

[void] $Form.ShowDialog()