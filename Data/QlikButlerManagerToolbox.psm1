<#

.SINOSSI

    Raccolta di funzioni per l'installazione e la disinstallazione di Qlik Butler su un cluster o un gruppo di essi.

.DESCRIZIONE

    Qlik Butler è una raccolta di script per la gestione di un cluster di Qlik Sense.
    Tramite questo script viene effettuata l'installazione di Qlik Butler su tutti i nodi del cluster.
    Il nodo centrale possiede tutti gli strumenti di Qlik Butler, mentre il rim solo la funzionalità di riavvio dei servizi.
    Funziona sia per Qlik Sense che per NPrinting.

.NOTE

    Autori: Matteo Silvestro
    Versione: 3.0.8
    Ultimo aggiornamento: 04/02/2020

#>

$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }
$BasePath = "$InstallPath\QlikButlerManager\"

<#

.SINOSSI
    Importa un file di configurazione.

.SINTASSI
    Import-ConfigFile [-ConfigFile] <string>

#>
function Import-ConfigFile {

    param(
        [string] $ConfigFile
    )

    Get-Content $ConfigFile | ForEach-Object -Begin { $Config=@{} } -Process { $k = [regex]::split($_, '='); if(($k[0].CompareTo('') -ne 0) -and ($k[0].StartsWith('[') -ne $True)) { $Config.Add($k[0].Trim(), $k[1].Trim()) } }
    return $Config

}

$SystemConfig = Import-ConfigFile -ConfigFile $BasePath\Data\System.config
$QlikAdministratorUser = $SystemConfig.QlikAdministratorUser
$QlikAdministratorPassword = ConvertTo-SecureString -String $SystemConfig.QlikAdministratorPassword -AsPlainText -Force

function Get-QlikAdminCredentials {

    param(
        [string] $Node
    )

    return New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $QlikAdministratorUser, $QlikAdministratorPassword

}

function Get-EnabledQlikServices {
    
    param(
        [string] $Hostname,
        [string] $CentralNode,
        $Credentials
    )

    # i servizi abilitati del cluster sono sempre tutti per definizione.
    if ($Hostname -eq $CentralNode) {
        return @(
            "QlikSenseRepositoryDatabase",
            "QlikSenseRepositoryService",
            "QlikSenseProxyService",
            "QlikSenseEngineService",
            "QlikSenseSchedulerService",
            "QlikSensePrintingService",
            "QlikSenseServiceDispatcher"
        )
    }

    Invoke-Command -ComputerName $CentralNode -Credential $Credentials -ScriptBlock {
        param(
            [string] $Hostname
        )

        try {
            $CentralFQDN = ([System.Net.Dns]::GetHostByName($env:COMPUTERNAME)).Hostname
            Connect-Qlik $CentralFQDN -TrustAllCerts -UseDefaultCredentials | Out-Null
            $NodeConfiguration = Get-QlikNode -filter "hostName sw '$Hostname'" -full
            $QlikServices = @()
            $QlikServices += "QlikSenseRepositoryService"            
            if ($NodeConfiguration.proxyEnabled) {
                $QlikServices += "QlikSenseProxyService"
            }
            if ($NodeConfiguration.engineEnabled) {
                $QlikServices += "QlikSenseEngineService"
            }
            if ($NodeConfiguration.schedulerEnabled) {
                $QlikServices += "QlikSenseSchedulerService"
            }
            if ($NodeConfiguration.printingEnabled) {
                $QlikServices += "QlikSensePrintingService"
            }
            $QlikServices += "QlikSenseServiceDispatcher"
        } catch {
            $QlikServices = @()
            @(
                "QlikSenseRepositoryDatabase",
                "QlikSenseRepositoryService",
                "QlikSenseProxyService",
                "QlikSenseEngineService",
                "QlikSenseSchedulerService",
                "QlikSensePrintingService",
                "QlikSenseServiceDispatcher"
            ) | foreach {
                $Service = Get-Service -Include $_ | where { $_.Status -eq "Running" }
                if ($Service) { $QlikServices += $Service.Name }
            }
        }
        $QlikServices
    } -ArgumentList $Hostname

}

<#

.SINOSSI
    Installa Qlik Butler su un cluster di Qlik Sense.

.SINTASSI
    Install-QlikButler [-Acronimo] <string> [-Ambiente] <string> [[-InstallPath] <string>]

#>
function Install-QlikButler {

    param(
        [string] $Acronimo,
        [string] $Ambiente,
        [string] $InstallPath = "E:\Software\__PWSH",
        [string] $InstallationType = "Qlik Sense",
        [switch] $NoConfig = $false,
        [switch] $NoTasks = $false
    )

    Write-Host "`r`nInstallazione di Qlik Butler sul cluster $Acronimo $Ambiente ($InstallationType)" -BackgroundColor DarkCyan

    # Salva le credenziali dell'utenza tecnica per poter accedere in remoto alle macchine.
    $QlikAdminCredentials = Get-QlikAdminCredentials

    # Estrai le informazioni sul cluster dal file in base all'acronimo e all'ambito forniti.
    $Cluster = Import-Csv $BasePath\Data\NodiCluster.csv -Delimiter ';' | Where-Object { ($_.Acronimo -eq $Acronimo) -and ($_.Ambiente -eq $Ambiente) -and ($_.Installazione -eq $InstallationType) }
    $ClusterCentral = ($Cluster | Where-Object { $_.TipoNodo -eq "Central" }).Hostname -join ", "  # la divisione tra central e rim serve solo per il file di configurazione
    $ClusterRim = ($Cluster | Where-Object { $_.TipoNodo -eq "Rim" } ).Hostname -join ", "

    if (-not $Cluster) {
        Write-Error -Message "Il cluster $Acronimo $Ambiente ($InstallationType) non è stato trovato. Installazione interrotta." -ErrorAction Stop
    }

    # File di configurazione del cluster, che verrà salvato solo sul central.
    $ClusterConfig = @"
Acronimo = $Acronimo
Ambiente = $Ambiente
ClusterCentral = $ClusterCentral
ClusterRim = $ClusterRim
Installazione = $InstallationType
GiorniSvecchiamento = 2
"@

    # Installa Qlik Butler su ogni nodo del cluster.
    $Cluster | ForEach-Object {
        Write-Host "`r`nNodo $($_.Hostname)" -ForegroundColor DarkCyan

        $Session = New-PSSession -ComputerName $_.Hostname -Credential $QlikAdminCredentials
        $NodeType = $_.TipoNodo

        # Copia i file di Qlik Butler in base al nodo.
        Invoke-Command -Session $Session -ScriptBlock {
            param([string] $InstallPath)
            if (-not (Test-Path $InstallPath\QlikButler)) {
                New-Item -Path $InstallPath\QlikButler -ItemType Directory | Out-Null
            }
            if (-not (Test-Path $InstallPath\QlikButler\Data)) {
                New-Item -Path $InstallPath\QlikButler\Data -ItemType Directory | Out-Null
            }
            if (-not (Test-Path $InstallPath\Logs)) {
                New-Item -Path $InstallPath\Logs -ItemType Directory | Out-Null
            }
        } -ArgumentList $InstallPath
        Copy-Item -Path $BasePath\QlikButlerFiles\Data\* -ToSession $Session -Destination $InstallPath\QlikButler\Data
        if ($NodeType -eq "Rim") {
            # I rim hanno solo lo script per il riavvio dei servizi del nodo.
            Copy-Item -Path $BasePath\QlikButlerFiles\Restart-NodeService.ps1, $BasePath\QlikButlerFiles\QlikButlerGUI.ps1, $BasePath\QlikButlerFiles\Start-Commands.ps1 -ToSession $Session -Destination $InstallPath\QlikButler
        } elseif ($NodeType -eq "Central") {
            if ($InstallationType -eq "Qlik Sense") {
                # I central di Qlik Sense hanno l'installazione completa.
                Copy-Item -Path $BasePath\QlikButlerFiles\*.ps1 -ToSession $Session -Destination $InstallPath\QlikButler
            } elseif ($InstallationType -eq "NPrinting") {
                # I central di NPrinting non hanno gli strumenti specifici per Qlik Sense.
                Copy-Item -Path $BasePath\QlikButlerFiles\Restart-NodeService.ps1, $BasePath\QlikButlerFiles\Restart-ClusterService.ps1, $BasePath\QlikButlerFiles\Restart-ClusterService.ps1, $BasePath\QlikButlerFiles\Backup-Cluster.ps1, $BasePath\QlikButlerFiles\Clean-BackupFiles.ps1, $BasePath\QlikButlerFiles\QlikButlerGUI.ps1, $BasePath\QlikButlerFiles\Start-Commands.ps1 -ToSession $Session -Destination $InstallPath\QlikButler
            }
        }
        # Copia il file di configurazione del sistema.
        Copy-Item -Path $BasePath\Data\System.config -ToSession $Session -Destination $InstallPath\QlikButler\Data
        Write-Host "`r`nQlik Butler installato in '$InstallPath\QlikButler\'."

        if (-not $NoConfig) {
            Write-Host "`r`nIl nodo " -NoNewline
            Write-Host $_.Hostname -ForegroundColor Yellow -NoNewline
            Write-Host " di tipo " -NoNewline
            Write-Host $_.TipoNodo -ForegroundColor Yellow -NoNewline
            Write-Host " ha i seguenti servizi abilitati:"
            # Ottieni i servizi di Qlik Sense abilitati sul nodo.
            if ($InstallationType -eq "Qlik Sense") {
                $Services = (Get-EnabledQlikServices -Hostname $_.Hostname -CentralNode $ClusterCentral -Credentials $QlikAdminCredentials) -join ", "
            } elseif ($InstallationType -eq "NPrinting") {
                $Services = (Invoke-Command -ComputerName $_.Hostname -Credential $QlikAdminCredentials -ScriptBlock {
                    $QlikServices = @()
                    @(
                        "QlikNPrintingMessagingService",
                        "QlikNPrintingRepoService",
                        "QlikNPrintingWebEngine",
                        "QlikNPrintingScheduler",
                        "QlikNPrintingEngine"
                    ) | ForEach-Object { $QlikServices += (Get-Service -Include $_) }
                    $QlikServices
                } | Where-Object {$_.Status -eq "Running"}).Name -join ", "
            }
            Write-Host $Services

            # File di configurazione locale del nodo.
            Write-Output $_.Host
            $LocalConfig = @"
Nodo = $($_.Hostname)
Servizi = $Services
"@
        }

        Invoke-Command -Session $Session -ScriptBlock {
            param($NodeType, $InstallPath, $Acronimo, $Ambiente, $LocalConfig, $ClusterConfig, $NoConfig, $NoTasks, $InstallationType, $QlikAdministratorUser, $QlikAdministratorPassword)

            <#

            .SINOSSI
                Crea una nuova schedulazione giornaliera di uno script di Qlik Butler.

            .SINTASSI
                New-QlikButlerDailyTask [-TaskName] <string>  [-TaskDescription] <string> [-At] <string> [-Path] <string>

            #>
            function New-QlikButlerDailyTask {

                param(
                    [string] $TaskName,
					[string] $TaskDescription,
                    [string] $At,
                    [string] $Path
                )

                $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File $Path"
                $Trigger = New-ScheduledTaskTrigger -Daily -At $At
                $Settings = New-ScheduledTaskSettingsSet
                Register-ScheduledTask -TaskName "$TaskName" `
                                       -TaskPath "\QlikButler" `
                                       -Action $Action `
									   -Description "$TaskDescription" `
                                       -Trigger $Trigger `
                                       -User $QlikAdministratorUser `
                                       -Password $QlikAdministratorPassword `
                                       -Settings $Settings | Out-Null 

            }
			
			<#

            .SINOSSI
                Crea una nuova schedulazione mensile di uno script di Qlik Butler.

            .SINTASSI
                New-QlikButlerMonthlyTask [-TaskName] <string>  [-TaskDescription] <string>  [-DaysOfMonth] <string> [$At] <string> [-Path] <string>

            #>
			function New-QlikButlerMonthlyTask {

				param(
					[string] $TaskName,
					[string] $TaskDescription,
					[string] $DaysOfMonth,
					[string] $At,
					[string] $Path
				)

				# Usa l'oggetto COM Task Scheduler.
				$ScheduleService = New-Object -ComObject ("Schedule.Service")
				# Connettiti alla macchina locale (http://msdn.microsoft.com/en-us/library/windows/desktop/aa381833(v=vs.85).aspx).
				$ScheduleService.Connect()
				$QlikButlerTasks = $ScheduleService.GetFolder("\QlikButler")
			 
				$TaskDefinition = $ScheduleService.NewTask(0) 
				$TaskDefinition.RegistrationInfo.Description = "$TaskDescription"
				$TaskDefinition.Settings.Enabled = $true
				$TaskDefinition.Settings.AllowDemandStart = $true
			 
				# http://msdn.microsoft.com/en-us/library/windows/desktop/aa383915(v=vs.85).aspx
				$Trigger = ($TaskDefinition.Triggers).Create(4) # 4 = Monthly
				$Trigger.DaysOfMonth = $DaysOfMonth
				$Trigger.StartBoundary = ([datetime]::Now).ToString("yyyy-MM-dd") + "T$($At):00"
				$Trigger.Enabled = $true
			 
				# http://msdn.microsoft.com/en-us/library/windows/desktop/aa381841(v=vs.85).aspx
				$Action = $TaskDefinition.Actions.Create(0)
				$Action.Path = "PowerShell.exe"
				$Action.Arguments = "-File $Path"
			 
				# http://msdn.microsoft.com/en-us/library/windows/desktop/aa381365(v=vs.85).aspx
				# argomento 3: 6 =  TASK_CREATE_OR_UPDATE
				# argomento 6: 1 = TASK_LOGON_PASSWORD
				$QlikButlerTasks.RegisterTaskDefinition("$TaskName", $TaskDefinition, 6, $QlikAdministratorUser, $QlikAdministratorPassword, 1) | Out-Null

			}

            <#

            .SINOSSI
                Crea una nuova scorciatoia per l'interfaccia grafica di Qlik Butler.

            .SINTASSI
                New-QlikButlerShortcut [-ShortcutPath] <string>

            #>
            function New-QlikButlerShortcut {

                param(
                    [string] $ShortcutPath,
                    [switch] $QlikSenseCluster = $false,
                    [switch] $NPrintingCluster = $false
                )

                $WScriptShell = New-Object -ComObject WScript.Shell
                $Shortcut = $WScriptShell.CreateShortcut("$ShortcutPath\Qlik Butler.lnk")
                $Shortcut.Targetpath = "PowerShell.exe"
                $Shortcut.Arguments = "-WindowStyle Hidden -File $InstallPath\QlikButler\QlikButlerGUI.ps1$(if ($QlikSenseCluster) {" -QlikSenseCluster"} elseif ($NPrintingCluster) {" -NPrintingCluster"})"
                $Shortcut.WorkingDirectory = "$InstallPath\QlikButler"
                $Shortcut.IconLocation = "$InstallPath\QlikButler\Data\QlikButler.ico"
                $Shortcut.Save()

            }

            # Crea la variabile d'ambiente che contiene il percorso d'installazione
            [System.Environment]::SetEnvironmentVariable("QLIKBUTLER_PATH", $InstallPath, [System.EnvironmentVariableTarget]::Machine)

            # Crea il file di configurazione locale.
            if (-not $NoConfig) {
                $LocalConfig | Out-File -FilePath $InstallPath\QlikButler\Data\Local.config
                Write-Host "Creato file di configurazione locale " -NoNewline
                Write-Host "Local.config" -ForegroundColor Yellow -NoNewline
                Write-Host "."
            }

            if ($NodeType -eq "Central") {
                # Solo nel caso del central, crea anche il file di configurazione del cluster...
                if (-not $NoConfig) {
                    $ClusterConfig | Out-File -FilePath $InstallPath\QlikButler\Data\Cluster.config
                    Write-Host "Creato file di configurazione del cluster " -NoNewline
                    Write-Host "Cluster.config" -ForegroundColor Yellow -NoNewline
                    Write-Host "."
                }

                # ... e le schedulazioni per il backup.
                if (-not $NoTasks) {
                    New-QlikButlerDailyTask -TaskName "$($Acronimo)_$($Ambiente) - Backup $InstallationType" -TaskDescription "Esegui il backup del cluster." -At "11:00 PM" -Path "$InstallPath\QlikButler\Backup-Cluster.ps1"
                    Write-Host "Creata la schedulazione " -NoNewline
                    Write-Host "$($Acronimo)_$($Ambiente) - Backup $InstallationType" -ForegroundColor Yellow -NoNewline
                    Write-Host "."
                    New-QlikButlerDailyTask -TaskName "$($Acronimo)_$($Ambiente) - Svecchiamento Backup" -TaskDescription "Rimuovi i file di backup vecchi." -At "3:00 AM" -Path "$InstallPath\QlikButler\Clean-BackupFiles.ps1"
                    Write-Host "Creata la schedulazione " -NoNewline
                    Write-Host "$($Acronimo)_$($Ambiente) - Svecchiamento Backup" -ForegroundColor Yellow -NoNewline
                    Write-Host "."
					New-QlikButlerMonthlyTask -TaskName "$($Acronimo)_$($Ambiente) - Svecchiamento Licenze" -TaskDescription "Rimuovi i token delle licenze associate agli utenti che non hanno eseguito accesso negli ultimi 90 giorni." -DaysOfMonth 1 -At "04:00" -Path "$InstallPath\QlikButler\Clean-UserPasses.ps1"
                    Write-Host "Creata la schedulazione " -NoNewline
                    Write-Host "$($Acronimo)_$($Ambiente) - Svecchiamento Licenze" -ForegroundColor Yellow -NoNewline
                    Write-Host "."
                    New-QlikButlerDailyTask -TaskName "$($Acronimo)_$($Ambiente) - Pulizia lista utenti" -TaskDescription "Rimuovi gli utenti non attivi e disabilitati, per il GDPR." -At "6:00 AM" -Path "$InstallPath\QlikButler\Clean-UserList.ps1"
                    Write-Host "Creata la schedulazione " -NoNewline
                    Write-Host "$($Acronimo)_$($Ambiente) - Pulizia lista utenti" -ForegroundColor Yellow -NoNewline
                    Write-Host "."
                }
            }

            # Crea la scorciatoria per la GUI.
            $Param = @{}
            if ($NodeType -eq "Central") {
                if ($InstallationType -eq "Qlik Sense") {
                    $Param = @{QlikSenseCluster = $true}
                } elseif ($InstallationType -eq "NPrinting") {
                    $Param = @{NPrintingCluster = $true}
                }
            }
            New-QlikButlerShortcut -ShortcutPath $InstallPath @Param
            # Aggiungi una scorciatoia anche sul desktop di alcuni utenti selezionati.
            foreach ($User in @("u0j6065", "u0i2444", "u0g1361", "U374075", "qlikadministrator")) {
                if (Test-Path "C:\Users\$User\Desktop") {
                    New-QlikButlerShortcut -ShortcutPath "C:\Users\$User\Desktop" @Param
                }
            }
            Write-Host "Creata scorciatoia per l'interfaccia grafica."

            Write-Host "`r`nServizi superflui in arresto..."
            . $InstallPath\QlikButler\Start-Commands.ps1 -Command "Arresta e disabilita servizi superflui"
            
        } -ArgumentList $NodeType, $InstallPath, $Acronimo, $Ambiente, $LocalConfig, $ClusterConfig, $NoConfig, $NoTasks, $InstallationType, $SystemConfig.QlikAdministratorUser, $SystemConfig.QlikAdministratorPassword

        Remove-PSSession $Session
    }

}


<#

.SINOSSI
    Disinstalla Qlik Butler da un cluster di Qlik Sense.

.SINTASSI
    Uninstall-QlikButler [-Acronimo] <string> [-Ambiente] <string> [[-InstallPath] <string>]

#>
function Uninstall-QlikButler {

    param(
        [string] $Acronimo,
        [string] $Ambiente,
        [string] $InstallPath = "E:\Software\__PWSH",
        [string] $InstallationType = "Qlik Sense",
        [switch] $NoConfig = $false,
        [switch] $NoTasks = $false
    )

    Write-Host "`r`nDisinstallazione di Qlik Butler sul cluster $Acronimo $Ambiente" -BackgroundColor DarkCyan

    # Salva le credenziali dell'utenza tecnica per poter accedere in remoto alle macchine.
    $QlikAdminCredentials = Get-QlikAdminCredentials

    # Estrai le informazioni sul cluster dal file in base all'acronimo e all'ambito forniti.
    $Cluster = Import-Csv $BasePath\Data\NodiCluster.csv -Delimiter ';' | Where-Object { ($_.Acronimo -eq $Acronimo) -and ($_.Ambiente -eq $Ambiente) -and ($_.Installazione -eq $InstallationType) }

    if (-not $Cluster) {
        Write-Error -Message "Il cluster $Acronimo $Ambiente ($InstallationType) non è stato trovato. Disinstallazione interrotta." -ErrorAction Stop
    }

    # Disinstalla Qlik Butler da ogni nodo del cluster.
    $Cluster | ForEach-Object {
        Write-Host "`r`nNodo $($_.Hostname)" -ForegroundColor DarkCyan

        $NodeType = $_.TipoNodo
        $Session = New-PSSession -ComputerName $_.Hostname -Credential $QlikAdminCredentials
        Invoke-Command -Session $Session -ScriptBlock {
            param($NodeType, $InstallPath, $NoConfig, $NoTasks)

            Write-Host "`r`nRimozione degli strumenti di Qlik Butler."

            # Elimina la variabile d'ambiente che contiene il percorso d'installazione
            [System.Environment]::SetEnvironmentVariable("QLIKBUTLER_PATH", $null, [System.EnvironmentVariableTarget]::Machine)

            # Rimuovi tutti gli strumenti dalla cartella corrispondente, se esiste.
            if (Test-Path $InstallPath\QlikButler) {
                Remove-Item $InstallPath\QlikButler\*.ps1 -Force
                Write-Host "La cartella '$InstallPath\QlikButler' è stata rimossa."
                if ($NoConfig) {
                    Remove-Item  $InstallPath\QlikButler\Data\* -Exclude "*.config" -Force
                    Write-Host "Sono stati mantenuti i file di configurazione."
                } else {
                    Remove-Item  $InstallPath\QlikButler\Data\* -Force
                }
            } else {
                Write-Host "La cartella '$InstallPath\QlikButler' non esiste."
            }

            # Rimuovi la scorciatoia.
            if (Test-Path "$InstallPath\Qlik Butler.lnk") {
                Remove-Item "$InstallPath\Qlik Butler.lnk"
                Write-Host "Scorciatoia rimossa."
            } else {
                Write-Host "Scorciatoia non trovata."
            }

            if (($NodeType -eq "Central") -and (-not $NoTasks)) {
                Write-Host "`r`nRimozione delle schedulazioni."

                # Nel caso del central, rimuovi anche le schedulazioni.
                $Tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -eq "\QlikButler\"}
                if ($Tasks) {
                    Get-ScheduledTask | Where-Object { $_.TaskPath -eq "\QlikButler\"} | Unregister-ScheduledTask -Confirm:$false
                    Write-Host "Le schedulazioni di Qlik Butler sono state rimosse."
                } else {
                    Write-Host "Le schedulazioni di Qlik Butler non sono state trovate."
                }
            }
            
            
        } -ArgumentList $NodeType, $InstallPath, $NoConfig, $NoTasks

        Remove-PSSession $Session
    }

}

<#

.SINOSSI
    Ottieni tutti i cluster di un ambiente.

.SINTASSI
    Get-ClusterByAmbiente [-Ambiente] <string>

#>
function Get-ClusterByAmbiente {
    
    param(
        [string] $Ambiente,
        [string] $InstallationType = "Qlik Sense"
    )

    $NodiCluster = Import-Csv $BasePath\Data\NodiCluster.csv -Delimiter ';' | Where-Object { $_.Installazione -eq $InstallationType }
    $NodiAmbiente = $NodiCluster | Where-Object { $_.Ambiente -eq $Ambiente } | Select-Object -Property Ambiente, Acronimo -Unique
    return $NodiAmbiente

}

<#

.SINOSSI
    Ottieni la versione e/o la presenza o meno delle schedulazioni su un nodo.

.SINTASSI
    Get-QlikButlerVersion [-Node] <string> [-InstallPath <string>] [-GetVersion] [-GetTasks]

#>
function Get-QlikButlerVersion {

    param(
        [string] $Node,
        [string] $InstallPath = "E:\Software\__PWSH",
        [switch] $GetVersion = $false,
        [switch] $GetTasks = $false
    )

    $Session = New-PSSession -ComputerName $Node -Credential (Get-QlikAdminCredentials)

    if ($GetVersion) {
        $Version = Invoke-Command -Session $Session -ScriptBlock {

            param([string] $InstallPath)

            if (Test-Path -Path $InstallPath\QlikButler\Data\Version.txt) {
                Get-Content $InstallPath\QlikButler\Data\Version.txt
            } else {
                $false
            }

        } -ArgumentList $InstallPath
    }
    if ($GetTasks) {
        $Tasks = Invoke-Command -Session $Session -ScriptBlock {

            param([string] $InstallPath)

            $Tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -eq "\QlikButler\"}
            if ($Tasks) {
                $true
            } else {
                $false
            }

        } -ArgumentList $InstallPath
    }

    Remove-PSSession $Session

    if ($GetVersion -and $GetTasks) {
        return $Version, $Tasks
    } elseif ($GetVersion) {
        return $Version
    } elseif ($GetTasks) {
        return $Tasks
    }

}

<#

.SINOSSI
    Ottieni la versione e/o la presenza o meno delle schedulazioni su un cluster.

.SINTASSI
    Get-ClusterQlikButlerVersion [-Ambiente] <string> [-Acronimo] <string> [-GetVersion] [-GetTasks]

#>
function Get-ClusterQlikButlerVersion {

    param(
        [string] $Ambiente,
        [string] $Acronimo,
        [string] $InstallationType = "Qlik Sense",
        [switch] $GetVersion = $false,
        [switch] $GetTasks = $false
    )

    $NodiCluster = Import-Csv $BasePath\Data\NodiCluster.csv -Delimiter ';' | Where-Object { $_.Installazione -eq $InstallationType }
    # Ottieni il primo central del cluster (nel caso ce ne fossero più di uno).
    $CentralNode = @($NodiCluster | Where-Object { ($_.Ambiente -eq $Ambiente) -and ($_.Acronimo -eq $Acronimo) -and ($_.TipoNodo -eq "Central") } | Select-Object -ExpandProperty Hostname)[0]
    return (Get-QlikButlerVersion -Node $CentralNode -GetVersion:$GetVersion -GetTasks:$GetTasks)

}

<#

.SINOSSI
    Ottieni la versione e/o la presenza o meno delle schedulazioni su tutti i cluster di un ambiente.
    Il risultato è strutturato come una tabella.

.SINTASSI
    Get-ClusterQlikButlerVersion [-Ambiente] <string>

#>
function Get-AmbienteQlikButlerVersion {
    
    param(
        [string] $Ambiente,
        [string] $InstallationType = "Qlik Sense"
    )

    $ClusterAmbiente = (Get-ClusterByAmbiente -Ambiente $Ambiente -InstallationType $InstallationType) | Select-Object *, @{
        Name = "Versione"; Expression = {
            try {
                $Version = Get-ClusterQlikButlerVersion -Acronimo $_.Acronimo -Ambiente $_.Ambiente -InstallationType $InstallationType -GetVersion
            } catch {
                $Version = "Errore"
            }
            if ($Version) {
                $Version
            } else {
                "X"
            }
        }
    }, @{
        Name = "Sched."; Expression = {
            if (Get-ClusterQlikButlerVersion -Acronimo $_.Acronimo -Ambiente $_.Ambiente -InstallationType $InstallationType -GetTasks) {
                "Sì"
            } else {
                "No"
            }
        }
    }
    return $ClusterAmbiente

}

<#

.SINOSSI
    Ottieni lo stato dell'ultimo backup di un cluster.

.SINTASSI
    Get-ClusterBackupStatus [-Ambiente] <string> [-Acronimo] <string> [-InstallPath <string>] [-InstallationType <string>]

#>
function Get-ClusterBackupStatus {

    param(
        [string] $Ambiente,
        [string] $Acronimo,
        [string] $InstallPath = "E:\Software\__PWSH",
        [string] $InstallationType = "Qlik Sense"
    )

    $NodiCluster = Import-Csv $BasePath\Data\NodiCluster.csv -Delimiter ';' | Where-Object { $_.Installazione -eq $InstallationType }
    # Ottieni il primo central del cluster (nel caso ce ne fossero più di uno).
    $CentralNode = @($NodiCluster | Where-Object { ($_.Ambiente -eq $Ambiente) -and ($_.Acronimo -eq $Acronimo) -and ($_.TipoNodo -eq "Central") } | Select-Object -ExpandProperty Hostname)[0]

    $Session = New-PSSession -ComputerName $CentralNode -Credential (Get-QlikAdminCredentials)

    $BackupStatus = Invoke-Command -Session $Session -ScriptBlock {

        param([string] $InstallPath)

        if (Test-Path -Path $InstallPath\Logs\*-Sonda.log) {
            Get-Content $InstallPath\Logs\*-Sonda.log
        } else {
            $false
        }

    } -ArgumentList $InstallPath

    Remove-PSSession $Session

    return $BackupStatus

}

<#

.SINOSSI
    Controlla la raggiungibilità di una pagina web.

.SINTASSI
    Test-WebPage [-Url] <string>

.NOTE
    Se è presente un certificato viene ignorato.

#>
function Test-WebPage {
param(
    [string] $Url
)

    $Url = $Url.ToLower()

    # Ignora il certificato quando si esegue la richiesta HTTP.
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    # Per evitare l'errore "The request was aborted: Could not create SSL/TLS secure channel.".
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    try {
        # Esegui la richiesta web.
        $HTTP_Request = [system.Net.WebRequest]::Create($Url)
        $HTTP_Response = $HTTP_Request.GetResponse()
    } catch {
        # Ottieni la risposta della richiesta web in caso di errore.
        $HTTP_Response = $_.Exception.Response
    }

    $HTTP_Status = [int] $HTTP_Response.StatusCode

    if ($HTTP_Response) {
        $HTTP_Response.Close()
    }

    if ($HTTP_Status -eq 200) {
        return $true
    }
    else {
        return $false
    }

}

function Test-QlikSenseAccess {

    param(
        [string] $Hostname,
        [string] $Ambiente,
        [switch] $FullCheck = $false
    )

    $QlikAdminCredentials = Get-QlikAdminCredentials

    $PingResult = Test-NetConnection -ComputerName $Hostname

    if ($PingResult.PingSucceeded) {
        $RemoteSession = New-PSSession -ComputerName $Hostname -Credential $QlikAdminCredentials
        $HealthCheckResult = Invoke-Command -Session $RemoteSession -ScriptBlock {
            add-type @"
                using System.Net;
                using System.Security.Cryptography.X509Certificates;
                public class TrustAllCertsPolicy : ICertificatePolicy {
                    public bool CheckValidationResult(
                        ServicePoint srvPoint, X509Certificate certificate,
                        WebRequest request, int certificateProblem) {
                        return true;
                    }
                }
"@
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy # salta il controllo dei certificati
            $FQDN = ([System.Net.Dns]::GetHostByName(($env:computerName))).Hostname
            Invoke-WebRequest -Uri "https://$FQDN/engine/healthcheck/" -UseDefaultCredentials -UseBasicParsing
        }
        if ($FullCheck) {
            $QMCResult = Invoke-Command -Session $RemoteSession -ScriptBlock { Invoke-WebRequest -Uri "https://$FQDN/qmc" -UseDefaultCredentials -UseBasicParsing }
            $HubResult = Invoke-Command -Session $RemoteSession -ScriptBlock { Invoke-WebRequest -Uri "https://$FQDN/hub" -UseDefaultCredentials -UseBasicParsing }
        }
    } else {
        return $false
    }

    if ($FullCheck) {
        return $PingResult.PingSucceeded, $HealthCheckResult.StatusCode, $QMCResult.StatusCode, $HubResult.StatusCode
    } else {
        return $HealthCheckResult.StatusCode
    }

}

function Test-NPrintingAccess {

    param(
        [string] $Hostname,
        [string] $Ambiente,
        [switch] $FullCheck = $false
    )

    $QlikAdminCredentials = Get-QlikAdminCredentials

    $PingResult = Test-NetConnection -ComputerName $Hostname

    if ($PingResult.PingSucceeded) {
        $RemoteSession = New-PSSession -ComputerName $Hostname -Credential $QlikAdminCredentials
        $ConsoleResult = Invoke-Command -Session $RemoteSession -ScriptBlock {
            add-type @"
                using System.Net;
                using System.Security.Cryptography.X509Certificates;
                public class TrustAllCertsPolicy : ICertificatePolicy {
                    public bool CheckValidationResult(
                        ServicePoint srvPoint, X509Certificate certificate,
                        WebRequest request, int certificateProblem) {
                        return true;
                    }
                }
"@
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy # salta il controllo dei certificati
            $FQDN = ([System.Net.Dns]::GetHostByName(($env:computerName))).Hostname
            Invoke-WebRequest -Uri "https://$($FQDN):4993" -UseDefaultCredentials -UseBasicParsing
        }
    } else {
        return $false
    }

    if ($FullCheck) {
        return $PingResult.PingSucceeded, $ConsoleResult.StatusCode
    } else {
        return $ConsoleResult.StatusCode
    }

}

Export-ModuleMember Install-QlikButler
Export-ModuleMember Uninstall-QlikButler
Export-ModuleMember Get-ClusterByAmbiente
Export-ModuleMember Get-ClusterQlikButlerVersion
Export-ModuleMember Get-ClusterBackupStatus
Export-ModuleMember Test-WebPage
Export-ModuleMember Test-QlikSenseAccess
Export-ModuleMember Test-NPrintingAccess
Export-ModuleMember Get-QlikAdminCredentials
Export-ModuleMember Get-EnabledQlikServices