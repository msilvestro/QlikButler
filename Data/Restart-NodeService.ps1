param(
    [string] $Node
)

# Ottieni la directory da cui è stato lanciato lo script.
$ScriptPath = if ($psise) { Split-Path $psise.CurrentFile.FullPath } else { $PSScriptRoot }

Import-Module $ScriptPath\QlikButlerManagerToolbox.psm1

# Ottieni le credenziali per l'accesso alle macchine.
$QlikAdminCredentials = Get-QlikAdminCredentials

Invoke-Command -ComputerName $Node -Credential $QlikAdminCredentials -ScriptBlock {
    $InstallPath = [System.Environment]::GetEnvironmentVariable("QLIKBUTLER_PATH", [System.EnvironmentVariableTarget]::Machine)
    if (-not $InstallPath) { $InstallPath = "E:\Software\__PWSH" }
    . $InstallPath\QlikButler\Restart-NodeService.ps1
}