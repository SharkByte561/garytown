<# Notes
Gary Blok | GARYTOWN.COM
This script will download and install Dell Command Integration Suite if it is not already installed, then get the warranty information for the system
If you do NOT want to download and install the Dell Command Integration Suite, you can do it on a single test machine,
and then copy the C:\Program Files (x86)\Dell\CommandIntegrationSuite\ folder (yes, all of the stuff in the folder) to your own "package".

Since I'm hosting this script on GitHub, I didn't want to host the Dell Warranty CLI files, so I'm downloading the entire Suite Installer from Dell's site.

If my explaination of how you could create your own package to use doesn't make sense, let me know, and I'll try to explain it better.
#>


function Get-DellWarrantyInfo {
    #This will download and install Dell Command Integration Suite if it is not already installed, then get the warranty information for the system
    #Dell Command Integration Suite needs to be installed on the system
    #https://dl.dell.com/topicspdf/command-integration-suite_users-guide2_en-us.pdf

    <#
    If you use a CSV file, I'd recommend keeping it simple, and just have a ServiceTag column, and then the Service Tags only, one on each line.
    
    If you use with ConfigMgr DB, assumes the person running has rights to the CM DB.
    
    Intial Version 24.2.20.1
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ServiceTag,
        [Parameter(Mandatory=$false)]
        [string]$CSVImportPath, #Feed a CSV file with a ServiceTag column
        [Parameter(Mandatory=$false)]
        [string]$CMConnectionStringHost, #SCCM Host
        [Parameter(Mandatory=$false)]
        [string]$CMConnectionStringDBName, #SCCM DB Name (CM_XXX)
        #[Parameter(Mandatory=$false)]
        #[switch]$CMConnectionIntegratedSecurity, #Disabled, this is all I'm supporting, I'm assuing you have rights.       
        [Parameter(Mandatory=$false)]
        [switch]$Cleanup #Uninstalls Dell Command Integration Suite after running
    )
    
    function Install-CommandIntegrationSuite{
        $ScratchDir = "$env:TEMP\Dell"
        if (-not (Test-Path $ScratchDir)) { New-Item -ItemType Directory -Path $ScratchDir |out-null }
        $DellWarrantyCLIPath = "C:\Program Files (x86)\Dell\CommandIntegrationSuite\DellWarranty-CLI.exe"

        if (-not(Test-Path $DellWarrantyCLIPath)){

            #Download and install Dell Command Integration Suite (DellWarranty-CLI.exe) and Install
            $DCWarrURL = 'http://dl.dell.com/FOLDER12624112M/1/Dell-Command-Integration-Suite-for-System-Center_G31J8_WIN64_6.6.0_A00.EXE'
            $DCWarrPath = "$ScratchDir\Dell-Command-Integration-Suite-for-System-Center_G31J8_WIN64_6.6.0_A00.EXE"
            Write-Verbose -Message "Downloading Dell Command Integration Suite"
            Start-BitsTransfer -Source $DCWarrURL -Destination $DCWarrPath -CustomHeaders "User-Agent:BITS 42"
            Write-Verbose -Message "Installing Dell Command Integration Suite"
            write-verbose -Message "Start-Process -FilePath $DCWarrPath -ArgumentList `"/S /E=$ScratchDir`" -Wait -NoNewWindow"
            Start-Process -FilePath $DCWarrPath -ArgumentList "/S /E=$ScratchDir" -Wait -NoNewWindow
            $DCWarrMSI = Get-ChildItem -Path $ScratchDir -Filter 'DCIS*.exe' | Select-Object -ExpandProperty FullName
            write-verbose -Message "Start-Process -FilePath $DCWarrMSI -ArgumentList `"/S /V/qn`" -Wait -NoNewWindow"
            Start-Process -FilePath $DCWarrMSI -ArgumentList "/S /V/qn" -Wait -NoNewWindow
        }
    }
    # Get the service tag

    #Create Export Path
    $ExportPath = "$env:programdata\Dell\WarrantyExport.csv"
    if (-not (Test-Path "$env:programdata\Dell")) { New-Item -ItemType Directory -Path "$env:programdata\Dell" |out-null }
    write-verbose -Message "Export Path: $ExportPath"


    if ($CMConnectionStringHost -or $CMConnectionStringDBName) {
        if (-not($CMConnectionStringHost -and $CMConnectionStringDBName)) {
            Write-Host "If you use the CMConnectionString, you need to pass both the Host and DBName" -ForegroundColor Red
            return
        }
        #write-verbose -Message "Start-Process -FilePath $DellWarrantyCLIPath -ArgumentList `"/I=$($CSVImportPath) /E=$($ExportPath)`" -Wait -WindowStyle Hidden"
        Install-CommandIntegrationSuite
        $CLI = Start-Process -FilePath $DellWarrantyCLIPath -ArgumentList "/Ics=`"Data Source=$($CMConnectionStringHost);Database=$($CMConnectionStringDBName);Integrated Security=true;`" /E=$($ExportPath)" -Wait -WindowStyle Hidden -PassThru
        Write-Verbose -Message "CLI Exit Code: $($CLI.ExitCode)"
        $Data = Get-Content -Path $ExportPath | ConvertFrom-Csv
        return $data
    }



    #If a CSVImportPath is passed, use that, otherwise create a CSV file with the Service Tag
    if ($CSVImportPath) {
        Install-CommandIntegrationSuite
        $ServiceTag = (Get-Content -Path $CSVImportPath).Trim()
        Write-Verbose -Message "CSVImportPath Path: $CSVImportPath"
        write-verbose -Message "Start-Process -FilePath $DellWarrantyCLIPath -ArgumentList `"/I=$($CSVImportPath) /E=$($ExportPath)`" -Wait -WindowStyle Hidden"
        $CLI = Start-Process -FilePath $DellWarrantyCLIPath -ArgumentList "/I=$($CSVPath) /E=$($ExportPath)" -Wait -WindowStyle Hidden -PassThru
        Write-Verbose -Message "CLI Exit Code: $($CLI.ExitCode)"
        $Data = Get-Content -Path $ExportPath | ConvertFrom-Csv
        return $data
    }


    if (!($ServiceTag)) {
        $Manf = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer
        Write-Verbose -Message "Manufacturer: $Manf"
        if ($Manf -match "Dell") {
            $ServiceTag = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
            
        } else {
            Write-Host "This script is only for Dell systems, or pass it a ServiceTag" -ForegroundColor Red
            if ($Cleanup) {
                write-verbose "Cleanup"
                Write-Verbose -Message "Start-Process -FilePath $DCWarrMSI -ArgumentList `"/s /V/qn /x`" -Wait -NoNewWindow"        
                Start-Process -FilePath $DCWarrMSI -ArgumentList "/s /V/qn /x" -Wait -NoNewWindow
            }
            return
        }
    }
    Write-Verbose -Message "Service Tag: $ServiceTag"
    $CSVPath = "$env:programdata\Dell\ServiceTag.csv"
    
    if ($ServiceTag){$ServiceTag | Out-File -FilePath $CSVPath -Encoding utf8 -Force}
    else{Write-Host "No Service Tag found" -ForegroundColor Red; return}
    
    Write-Verbose -Message "CSV Path: $CSVPath"
    Write-Verbose -Message "Start-Process -FilePath $DellWarrantyCLIPath -ArgumentList `"/I=$($CSVPath) /E=$($ExportPath)`" -Wait -WindowStyle Hidden"
    $CLI = Start-Process -FilePath $DellWarrantyCLIPath -ArgumentList "/I=$($CSVPath) /E=$($ExportPath)" -Wait -WindowStyle Hidden -PassThru
    Write-Verbose -Message "CLI Exit Code: $($CLI.ExitCode)"
    $Data = Get-Content -Path $ExportPath | ConvertFrom-Csv

    if ($Cleanup) {
        write-verbose "Cleanup"
        Write-Verbose -Message "Start-Process -FilePath $DCWarrMSI -ArgumentList `"/s /V/qn /x`" -Wait -NoNewWindow"        
        Start-Process -FilePath $DCWarrMSI -ArgumentList "/s /V/qn /x" -Wait -NoNewWindow
    }
    return $data
}