param(
    [string] $Node
)

# Ottieni la directory da cui è stato lanciato lo script.
$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

Import-Module $ScriptPath\QlikButlerManagerToolbox.psm1

# Ottieni le credenziali per l'accesso alle macchine.
$Password = ConvertTo-SecureString -String (Get-Content "$ScriptPath\Pwd.txt") -AsPlainText -Force
$QlikAdminCredentials = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList "qlikadministrator", $Password

Invoke-Command -ComputerName $Node -Credential $QlikAdminCredentials -ScriptBlock {
    Get-Service "Qlik*" | foreach {
        $ServiceName = $_.Name
        Write-Host "Interruzione forzata $ServiceName..."
        $ServiceId = Get-WmiObject -Class Win32_Service -Filter "Name LIKE '$ServiceName'" | Select-Object -ExpandProperty ProcessId
        Stop-Process -Id $ServiceId -Force
    }
}