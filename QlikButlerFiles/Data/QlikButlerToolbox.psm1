<#

.SINOSSI

    Raccolta di funzioni per gestire i servizi di Qlik Sense e NPrinting.

.DESCRIZIONE

    Le funzioni:
    * Import-ConfigFile    Importa un file di configurazione.
    * Get-QlikService      Restituisce le informazioni sui servizi del computer locale.
    * Start-QlikService    Avvia i servizi Qlik della macchina locale nell'ordine corretto.
    * Stop-QlikService     Arresta i servizi di Qlik della macchina locale nell'ordine inverso rispetto a quello di avvio.
    * Test-WebPage         Controlla la raggiungibilità di una pagina web.
    * Test-QlikSenseAccess Controlla la raggiungibilità dell'Hub di Qlik.
    * Test-NPrintingAccess Controlla la raggiungibilità della console web di NPrinting.

.NOTE

    Autore: Matteo Silvestro
    Versione: 3.0.3
    Ultimo aggiornamento: 26/11/2019

#>

<#

.SINOSSI
    Importa un file di configurazione.

.SINTASSI
    Import-ConfigFile [-ConfigFile] <string>

#>
function Import-ConfigFile {

    param (
        [string] $ConfigFile
    )

    Get-Content $ConfigFile | ForEach-Object -Begin { $Config=@{} } -Process { $k = [regex]::split($_, '='); if(($k[0].CompareTo('') -ne 0) -and ($k[0].StartsWith('[') -ne $True)) { $Config.Add($k[0].Trim(), $k[1].Trim()) } }
    return $Config

}

function Split-ConfigLine {

    param (
        [string] $ConfigLine
    )

    return $ConfigLine.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } # ignora eventuali elementi vuoti

}

# Ottieni la directory in cui è stato installato Qlik Butler.
$InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }

# Estrai le variabili di configurazione.
$LocalConfig = Import-ConfigFile -ConfigFile $InstallPath\QlikButler\Data\Local.config
$SystemConfig = Import-ConfigFile -ConfigFile $InstallPath\QlikButler\Data\System.config
$NodeName = $LocalConfig.Nodo
$NodeServices = Split-ConfigLine -ConfigLine $LocalConfig.Servizi
$QlikAdministratorUser = $SystemConfig.QlikAdministratorUser
$QlikAdministratorPassword = ConvertTo-SecureString -String $SystemConfig.QlikAdministratorPassword -AsPlainText -Force

function Get-NodeName {

    return $NodeName

}

<#

.SINOSSI
    Ottieni informazioni sui servizi Qlik sul computer locale.
    Funziona sia per Qlik Sense che NPrinting.

.SINTASSI
    Get-QlikService

.LINK
    Riferimento per il corretto ordine di avvio dei servizi di Qlik Sense: https://support.qlik.com/articles/000010331.

.NOTE
    L'ordine dei servizi è importante e può impattare il corretto funzionamento dello script.

#>
function Get-QlikService {

    if ($NodeServices) {
        $Services = $NodeServices
    } else {
        Write-Warning "File di configurazione locale '$InstallPath\QlikButler\Data\Local.config' non trovato. Vengono restituiti i servizi completi di Qlik Sense."
        $Services = @(
            "QlikSenseRepositoryDatabase",
            "QlikSenseRepositoryService",
            "QlikSenseProxyService",
            "QlikSenseEngineService",
            "QlikSenseSchedulerService",
            "QlikSensePrintingService",
            "QlikSenseServiceDispatcher"
        )
    }

    return $Services

}

function Get-QlikAdminCredentials {

    return New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $QlikAdministratorUser, $QlikAdministratorPassword

}

<#

.SINOSSI
    Avvia i servizi Qlik sulla macchina locale nell'ordine corretto.
    Funziona sia per Qlik Sense che NPrinting.

.SINTASSI
    Start-QlikService [[-Services] <String[]>] [-Exclude [<String[]>]

#>
function Start-QlikService {
    
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string] $Node,
        [string[]] $Services,
        [string[]] $Exclude = @()
    )

    process { # per gestire tutti gli elementi della pipeline
        if ($Node) {
            Invoke-Command -ComputerName $Node -Credential (Get-QlikAdminCredentials) -ScriptBlock {
                param($Services, $Exclude)
                $InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
                if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }
                Import-Module $InstallPath\QlikButler\Data\QlikButlerToolbox.psm1
                Start-QlikService -Services $Services -Exclude $Exclude
            } -ArgumentList $Services, $Exclude
        } else {
            Start-LocalQlikService -Services $Services -Exclude $Exclude
        }
    }

}

function Start-LocalQlikService {

    param (
        [string[]] $Services,
        [string[]] $Exclude = @()
    )

    Write-Output "`r`n# Avvio servizi su $(Get-NodeName)"

    if (-not $Services) {
        $Services = Get-QlikService
    } else {
        $Services = $Services | Where-Object { $_ -in (Get-QlikService) }
    }
    if ($Exclude.Length -ne 0) {
        $Services = $Services | Where-Object { $_ -notin $Exclude }
    }

    ForEach ($Service in $Services) {
        Write-Output "Avvio servizio $Service..."
        try {
            Set-Service -Name $Service -StartupType Automatic
            Start-Service -Name $Service -ErrorAction Stop
        } catch {
            Write-Output "! Errore nell'avvio del servizio."
        }
        $Status = (Get-Service -Name $Service).Status
        Write-Output "-> $Service in stato: $Status."
        # Aspetta un secondo per evitare possibili accavallamenti dei servizi.
        Start-Sleep -Seconds 1
    }

}

<#

.SINOSSI
    Arresta i servizi Qlik sulla macchina locale nell'ordine corretto.
    Funziona sia per Qlik Sense che NPrinting.

.SINTASSI
    Stop-QlikService [[-Services] <String[]>] [-Exclude [<String[]>]

.NOTE
    L'ordine di arresto dei servizi è inverso rispetto all'ordine di avvio.
    Per questo motivo, lo script prende in considerazione l'ordine di avvio dei servizi, che viene successivamente invertito.
    Nel caso ci sia un errore nell'arresto del servizio, viene tentata l'interruzione del processo associato.

#>
function Stop-QlikService {
    
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string] $Node,
        [string[]] $Services,
        [string[]] $Exclude = @()
    )

    process { # per gestire tutti gli elementi della pipeline
        if ($Node) {
            Invoke-Command -ComputerName $Node -Credential (Get-QlikAdminCredentials) -ScriptBlock {
                param($Services, $Exclude)
                $InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
                if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }
                Import-Module $InstallPath\QlikButler\Data\QlikButlerToolbox.psm1
                Stop-QlikService -Services $Services -Exclude $Exclude
            } -ArgumentList $Services, $Exclude
        } else {
            Stop-LocalQlikService -Services $Services -Exclude $Exclude
        }
    }

}

function Stop-LocalQlikService {

    param (
        [string[]] $Services,
        [string[]] $Exclude = @()
    )

    Write-Output "`r`n# Arresto servizi su $(Get-NodeName)"

    if (-not $Services) {
        $Services = Get-QlikService
    } else {
        $Services = $Services | Where-Object { $_ -in (Get-QlikService) }
    }
    if ($Exclude.Length -ne 0) {
        $Services = $Services | Where-Object { $_ -notin $Exclude }
    }

    if ($Services) { [array]::Reverse($Services) } # l'ordine di arresto dei servizi deve essere l'inverso di quello di avvio

    ForEach ($Service in $Services) {
        Write-Output "Arresto servizio $Service..."
        try {
            Set-Service -Name $Service -StartupType Disable
            Stop-Service -Name $Service -Force -ErrorAction Stop
        } catch {
            Write-Output "! Errore nell'arresto del servizio."
            # Se non si riesce ad arrestare il servizio, tentare l'interruzione forzata del processo associato.
            #Write-Output "Problema nell'arresto del servizio, tentativo di interruzione forzata..."
            #$ServiceId = Get-WmiObject -Class Win32_Service -Filter "Name LIKE '$Service'" | Select-Object -ExpandProperty ProcessId
            #Stop-Process -Id $ServiceId -Force
        }
        $Status = (Get-Service -Name $Service).Status
        Write-Output "-> $Service in stato: $Status."
        Start-Sleep -Seconds 1
    }

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

    param (
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

    $HTTP_Status = [int]$HTTP_Response.StatusCode

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

<#

.SINOSSI
    Controlla la raggiungibilità dell'Hub di un'installazione Qlik Sense.

.SINTASSI
    Test-QlikSenseAccess [-ComputerName] <string>

#>
function Test-QlikSenseAccess {

    param (
        [string] $ComputerName = $env:COMPUTERNAME
    )

    Return Test-WebPage -Url "https://$ComputerName/hub"

}

<#

.SINOSSI
    Controlla la raggiungibilità della console web di NPrinting.

.SINTASSI
    Test-NPrintingAccess [-ComputerName] <string>

#>
function Test-NPrintingAccess {

    param (
        [string] $ComputerName = $env:computername
    )

    Return Test-WebPage -Url "https://$($ComputerName):4993/"

}

function Get-FileByFileDialog {

    param (
        [string] $TypeFilter
    )

    Add-Type -AssemblyName System.Windows.Forms
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        InitialDirectory = [Environment]::GetFolderPath('MyDocuments');
        Filter = $TypeFilter
    }
    $FileBrowserResult = $FileBrowser.ShowDialog()
    if ($FileBrowserResult -eq "OK") {
        $SourceAppPath = $FileBrowser.FileName
        Write-Host "Selezionato il file '$SourceAppPath'."
        return $SourceAppPath
    } elseif ($FileBrowserResult -eq "Cancel") {
        Write-Host "Operazione annullata."
        return $false
    } else {
        Write-Host "Errore '$FileBrowserResult'."
        return $false
    }

}

function Get-FolderByFolderDialog {

    Add-Type -AssemblyName System.Windows.Forms
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
        SelectedPath = [Environment]::GetFolderPath('MyDocuments');
    }
    $FolderBrowserResult = $FolderBrowser.ShowDialog()
    if ($FolderBrowserResult -eq "OK") {
        $Path = $FolderBrowser.SelectedPath
        Write-Host "Selezionato il percorso '$Path'."
        return $Path
    } elseif ($FolderBrowserResult -eq "Cancel") {
        Write-Host "Operazione annullata."
        return $false
    } else {
        Write-Host "Errore '$FolderBrowserResult'."
        return $false
    }

}

Export-ModuleMember -Function Import-ConfigFile
Export-ModuleMember -Function Split-ConfigLine
Export-ModuleMember -Function Get-NodeName
Export-ModuleMember -Function Get-QlikService
Export-ModuleMember -Function Start-QlikService
Export-ModuleMember -Function Stop-QlikService
Export-ModuleMember -Function Test-WebPage
Export-ModuleMember -Function Test-QlikSenseAccess
Export-ModuleMember -Function Test-NPrintingAccess
Export-ModuleMember -Function Get-FileByFileDialog
Export-ModuleMember -Function Get-FolderByFolderDialog