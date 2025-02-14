<#
.SYNOPSIS
    This script will create the folders, scripts, and tasks for performing basic StifleR maintenance.

.DESCRIPTION
    The script sets up the necessary directory structure, places the required scripts, and creates scheduled tasks to automate StifleR maintenance tasks.

.AUTHOR
    2Pint Software

.VERSION
    25.2.14
#>


#Please ensure that the following folders exist before running this script, adjust the paths as necessary
#$StifleRParentFolder = "C:\Program Files\2Pint Software"
$StifleRInstallFolder = (Get-ItemPropertyValue -Path HKLM:\SYSTEM\CurrentControlSet\Services\StifleRServer -Name ImagePath | Split-Path -Parent).Replace('"','')
$StifleRParentFolder = $StifleRInstallFolder | split-Path -Parent
$gMSAAccountName = 'gMSAStifleR$'

#Create Folder Structure
$StifleRMaintenanceFolder = "$StifleRParentFolder\StifleR Maintenance"
$StifleRMaintenanceLogFolder = "$ENV:ProgramData\2Pint Software\StifleR Maintenance Logs"

# Create the StifleR Maintenance folder if it doesn't exist
if (-Not (Test-Path -Path $StifleRMaintenanceFolder)) {
    New-Item -ItemType Directory -Path $StifleRMaintenanceFolder -Force | Out-Null
}

# Create the StifleR Maintenance Log folder if it doesn't exist
if (-Not (Test-Path -Path $StifleRMaintenanceLogFolder)) {
    New-Item -ItemType Directory -Path $StifleRMaintenanceLogFolder -Force | Out-Null
}

function Test-ScheduledTaskExists {
    param (
        [string]$TaskName
    )

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        return $true
    } else {
        return $false
    }
}

#Creates Scheduled Task in 2Pint Software Folder in Scheduled Tasks
function New-StifleRMaintenanceTask {
    param (
        [string]$TaskName = "StifleRMaintenance",
        [string]$ScriptPath = "C:\Program Files\2Pint Software\StifleR Maintenance\script.ps1",
        [string]$gMSAAccountName = "gMSA_StifleRMaintenance",
        [string]$timeofday = "2:00AM"
    )
    
    if (Test-ScheduledTaskExists -TaskName $TaskName) {
        Write-Host "Scheduled task '$TaskName' already exists."
        return
    }
    
    # Define the name of the new folder
    $folderName = "2Pint Software"

    # Create a new scheduled task folder
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    try {
        $taskService.GetFolder("$folderName") | Out-Null
    }
    catch {
        $rootFolder = $taskService.GetFolder("\")
        $rootFolder.CreateFolder($folderName) | Out-Null
    }

    Write-Output "Scheduled task folder '$folderName' created successfully."
    
    # Define the action for the scheduled task
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

    # Define the trigger for the scheduled task (daily at 2 AM)
    $trigger = New-ScheduledTaskTrigger -Daily -At $timeofday
    # Define the settings for the scheduled task
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew -DisallowStartIfOnRemoteAppSession -RunOnlyIfNetworkAvailable -RunLevel Highest

    # Define the principal for the scheduled task
    $principal = New-ScheduledTaskPrincipal -UserId $gMSAAccountName -LogonType Password -RunLevel Highest
    # Register the scheduled task
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName -Description "Daily StifleR Maintenance Task" -TaskPath "\2Pint Software" -Force -Settings $settings -Principal $principal
}


# Example usage
#New-StifleRMaintenanceTask

#Create Maintenance Scripts - Clean up Stale Objects
$RemoveStifleRStaleClientsScriptContent = @'
<#
.SYNOPSIS
    Maintenance task that removes 'stale' clients from the StifleR DB  - that haven't checked in for xx days
.DESCRIPTION
    See above :)
    Outputs results to a logfile
.REQUIREMENTS
    Run on the StifleR Server
.USAGE
    Set the path to the logfile
    .\Remove-StifleRStaleClients.ps1
.NOTES
    AUTHOR: 2Pint Software
    EMAIL: support@2pintsoftware.com
    VERSION: 25.02.14
    CHANGE LOG:
    25.02.13  : Initial version of script
    25.02.14  : Replaced log function, removed redundant logging info
.LINK
    https://2pintsoftware.com
#>

# Change these two variables to match your environment!
$LogPath = "$ENV:ProgramData\2Pint Software\StifleR Maintenance Logs"
$NumberOfDays = 30

# Ok, lets do this...
$Date = $(get-date -f MMddyyyy_hhmmss)
$Logfile = "$LogPath\Remove-StifleRStaleClients_$Date.log"

Function Write-Log {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false)]
        $Message,
        [Parameter(Mandatory=$false)]
        $ErrorMessage,
        [Parameter(Mandatory=$false)]
        $Component = "Script",
        [Parameter(Mandatory=$false)]
        [int]$Type,
        [Parameter(Mandatory=$false)]
        $LogFile = $LogFile
    )
    <#
    Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
    #>
    $Time = Get-Date -Format "HH:mm:ss.ffffff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    if ($ErrorMessage -ne $null) {$Type = 3}
    if ($Component -eq $null) {$Component = " "}
    if ($Type -eq $null) {$Type = 1}
    $LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $LogMessage.Replace("`0","") | Out-File -Append -Encoding UTF8 -FilePath $LogFile
}

Write-Log "Starting Client Cleanup."

$Clients = Get-CimInstance -Namespace root\StifleR -Class "Clients"
$TotalClients = ($Clients | Measure-Object).Count
Write-Log "There are currently $TotalClients Clients in the DB."

$DateFilter = ([wmi]"").ConvertFromDateTime((get-date).AddDays(-$NumberOfDays))
$ClientsToRemove = Get-CimInstance -Namespace root\StifleR -Class "Clients" -Filter "DateOnline < '$DateFilter'"
$TotalToRemove = ($ClientsToRemove | Measure-Object).Count

if ($TotalToRemove -eq 0) {
    Write-Log "Found $TotalToRemove clients more than $NumberOfDays old - no clients to clean up"
} else {
    Write-Log "---------------------------------------------------------------"
    Write-Log "Removing StifleR Clients not reporting in the last $NumberOfDays"
    Write-Log "Found $TotalToRemove clients"
    Write-Log "---------------------------------------------------------------"

    ForEach ($Client in $ClientsToRemove) {
        $ClientName = $Client.ComputerName
        $LastCheckin = $Client.DateOnline

        Try {
            Invoke-CimMethod -InputObject $Client -MethodName RemoveFromDB | Out-Null
        } Catch {
            Write-Log "Failed to remove Client $ClientName, $LastCheckin"
            Write-Log $_.Exception
            throw  $_.Exception
        }

        Write-Log "Removed Client from DB Name: $ClientName, Last Checkin: $LastCheckin"
    }

    Write-Log "Removed $TotalToRemove Clients"
}

Write-Log "Remove-StifleRStaleClients all done, over and out!"
'@

$RemoveStifleRStaleClientsScriptContent | Out-File -FilePath "$StifleRMaintenanceFolder\Remove-StifleRStaleClients.ps1" -Force
New-StifleRMaintenanceTask -TaskName "Remove StifleR Stale Clients" -ScriptPath "$StifleRMaintenanceFolder\Remove-StifleRStaleClients.ps1" -gMSAAccountName $gMSAAccountName -timeofday "3:00AM"


#Create Maintenance Scripts - Clean up Duplicate Objects
$RemoveStifleRDuplicateClientsScriptContent = @'
<#
.SYNOPSIS
    Maintenance task that removes 'stale' clients from the StifleR DB  - that haven't checked in for xx days
.DESCRIPTION
    See above :)
    Outputs results to a logfile
.REQUIREMENTS
    Run on the StifleR Server
.USAGE
    Set the path to the logfile
    .\Remove-StifleRStaleClients.ps1
.NOTES
    AUTHOR: 2Pint Software
    EMAIL: support@2pintsoftware.com
    VERSION: 25.02.14
    CHANGE LOG:
    25.02.13  : Initial version of script
    25.02.14  : Replaced log function, removed redundant logging info
.LINK
    https://2pintsoftware.com
#>

# Change these two variables to match your environment!
$LogPath = "$ENV:ProgramData\2Pint Software\StifleR Maintenance Logs"
$NumberOfDays = 30

# Ok, lets do this...
$Date = $(get-date -f MMddyyyy_hhmmss)
$Logfile = "$LogPath\Remove-StifleRStaleClients_$Date.log"

Function Write-Log {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false)]
        $Message,
        [Parameter(Mandatory=$false)]
        $ErrorMessage,
        [Parameter(Mandatory=$false)]
        $Component = "Script",
        [Parameter(Mandatory=$false)]
        [int]$Type,
        [Parameter(Mandatory=$false)]
        $LogFile = $LogFile
    )
    <#
    Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
    #>
    $Time = Get-Date -Format "HH:mm:ss.ffffff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    if ($ErrorMessage -ne $null) {$Type = 3}
    if ($Component -eq $null) {$Component = " "}
    if ($Type -eq $null) {$Type = 1}
    $LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $LogMessage.Replace("`0","") | Out-File -Append -Encoding UTF8 -FilePath $LogFile
}

Write-Log "Starting Client Cleanup."

$Clients = Get-CimInstance -Namespace root\StifleR -Class "Clients"
$TotalClients = ($Clients | Measure-Object).Count
Write-Log "There are currently $TotalClients Clients in the DB."

$DateFilter = ([wmi]"").ConvertFromDateTime((get-date).AddDays(-$NumberOfDays))
$ClientsToRemove = Get-CimInstance -Namespace root\StifleR -Class "Clients" -Filter "DateOnline < '$DateFilter'"
$TotalToRemove = ($ClientsToRemove | Measure-Object).Count

if ($TotalToRemove -eq 0) {
    Write-Log "Found $TotalToRemove clients more than $NumberOfDays old - no clients to clean up"
} else {
    Write-Log "---------------------------------------------------------------"
    Write-Log "Removing StifleR Clients not reporting in the last $NumberOfDays"
    Write-Log "Found $TotalToRemove clients"
    Write-Log "---------------------------------------------------------------"

    ForEach ($Client in $ClientsToRemove) {
        $ClientName = $Client.ComputerName
        $LastCheckin = $Client.DateOnline

        Try {
            Invoke-CimMethod -InputObject $Client -MethodName RemoveFromDB | Out-Null
        } Catch {
            Write-Log "Failed to remove Client $ClientName, $LastCheckin"
            Write-Log $_.Exception
            throw  $_.Exception
        }

        Write-Log "Removed Client from DB Name: $ClientName, Last Checkin: $LastCheckin"
    }

    Write-Log "Removed $TotalToRemove Clients"
}

Write-Log "Remove-StifleRStaleClients all done, over and out!"
'@

$RemoveStifleRDuplicateClientsScriptContent | Out-File -FilePath "$StifleRMaintenanceFolder\Remove-StifleRDuplicates.ps1" -Force
New-StifleRMaintenanceTask -TaskName "Remove StifleR Duplicate Clients" -ScriptPath "$StifleRMaintenanceFolder\Remove-StifleRDuplicates.ps1" -gMSAAccountName $gMSAAccountName -timeofday "4:00AM"