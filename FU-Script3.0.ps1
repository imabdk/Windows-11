<#
.SYNOPSIS
    This script creates files, folders as well as all the custom scripts possibly needed when upgrading to Windows 11 as a Feature Update

.DESCRIPTION
    The script create a FeatureUpdate folder in ProgramData, as well as 4 custom scripts: 
    SetupComplete.cmd, SetupComplete.ps1, PostRollBack.cmd, PostRollBack.ps1

    The script also create a WSUS folder in LocalAppData in the Default userprofile, as well as a SetupConfig.ini file

    This script is intended to be run as a preliminary step using Intune or Configuration Manager

.NOTES
    Filename: FU-Script.ps1
    Version: 3.0
    Author: Martin Bengtsson
    Blog: www.imab.dk
    Twitter: @mwbengtsson

    Version history:

    1.0   -   Script created
    2.0   -   Added option to send notifications to a Teams channel
                - Use the option $sendStatusTeams = $true
    3.0   -   Added option to escrow BitLocker recovery keys to Azure AD
                - Use the option $bitLockerRecoveryKeystoAAD = $true

.LINK
    https://www.imab.dk/remove-built-in-teams-app-and-chat-icon-in-windows-11-during-a-feature-update-via-setupconfig-ini-and-setupcomplete-cmd
    https://www.imab.dk/monitor-your-windows-11-feature-updates-with-custom-action-scripts-and-notifications-send-to-microsoft-teams
    https://www.imab.dk/escrow-bitlocker-recovery-keys-to-azure-ad-during-feature-update-to-windows-11
#>

# Global variables
$global:iniFileFolderPath = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\WSUS"
$global:iniFilePath = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\WSUS\SetupConfig.ini"
$global:featureUpdateFolder = "$env:ALLUSERSPROFILE\FeatureUpdates"
# Functions
function Create-FeatureUpdatesFolders() {
    Write-Verbose -Verbose -Message "Running Create-FeatureUpdateFolders function"
    if (-NOT(Test-Path -Path $iniFileFolderPath)) {
        New-Item -Path $iniFileFolderPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
    if (-NOT(Test-Path -Path $featureUpdateFolder)) {
        New-Item -Path $featureUpdateFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
}
function Create-CustomActionScript() {
    [CmdletBinding()]
    param (
        [Parameter(Position="0")]
        [ValidateSet("SetupComplete","PostRollBack")]
        [string]$Type,
        [Parameter(Position="1")]
        [String]$Path = $global:featureUpdateFolder
    )
    Write-Verbose -Verbose -Message "Running Create-CustomActionScript function: $Type"
    switch ($Type) {
        SetupComplete {
            # CMD file
            $CMDFileName = $Type + '.cmd'
            $CMDFilePath = $Path + '\' + $CMDFileName
            New-item -Path $Path -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
            $GetCustomScriptPath = $PathInfo.FullName
            [String]$Script = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -WindowStyle Hidden -File `"$global:featureUpdateFolder\SetupComplete.ps1`""
            if (-NOT[string]::IsNullOrEmpty($Script)) {
                Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
            }
 
            # PS1 file
            $PS1FileName = $Type + '.ps1'
            $PS1FilePath = $Path + '\' + $PS1FileName
            New-item -Path $Path -Name $PS1FileName -Force -OutVariable PathInfo | Out-Null
            $GetCustomScriptPath = $PathInfo.FullName
            [String]$Script = @'
# Script goes here

<#
.SYNOPSIS
    SetupComplete.ps1 file located in ProgramData\FeatureUpdates. Will be initiated by SetupComplete.cmd referenced by SetupConfig.ini
   
.DESCRIPTION
    Same as above

.NOTES
    Filename: SetupComplete.ps1
    Version: 3.0
    Author: Martin Bengtsson
    Blog: www.imab.dk
    Twitter: @mwbengtsson
#>

# Variables
$companyName = "imab.dk"
$targetWindowsBuild = "21H2"
$registryPath = "HKLM:\SOFTWARE\$companyName\WaaS\$targetWindowsBuild"
$runDateTime = Get-Date -Format g

# Escrow BitLocker recovery keys to Azure AD
$bitLockerRecoveryKeystoAAD = $true
# Teams message card variables
$sendStatusTeams = $true
$webhookUri = "<INSERT WEBHOOKE URI>"
$computerName = (Get-WmiObject -Class Win32_ComputerSystem).Name
$computerMake = (Get-WmiObject -Class Win32_BIOS).Manufacturer
$computerModel = (Get-WmiObject -Class Win32_ComputerSystem).Model
$ipAddress = (Get-WmiObject win32_Networkadapterconfiguration | Where-Object{ $_.ipaddress -notlike $null }).IPaddress | Select-Object -First 1
$body = @"
{
    "@type": "MessageCard",
    "@context": "https://schema.org/extensions",
    "summary": "WaaS Monitoring",
    "themeColor": "f07f13",
    "title": "Upgrade of $($computerName): SUCCESS!",
    "sections": [
     {
            "activityTitle": "Kromann Reumert OSD",
            "activitySubtitle": "Windows 11 v21H2 Feature Update",
            "activityImage": "https://github.com/imabdk/Images/blob/main/success.png?raw=true",
            "activityText": "",
            
            "facts": [
                {
                    "name": "Computername:",
                    "value": "$computerName"
                },
                {
                    "name": "Run date/time:",
                    "value": "$runDateTime"
                },
                {
                    "name": "IP address:",
                    "value": "$ipAddress"
                },
                {
                    "name": "Manufacturer:",
                    "value": "$computerMake"
                },
                {
                    "name": "Model:",
                    "value": "$computerModel"
                }
            ],
            "text": "<h2 style=color:#f07f13;>DEPLOYMENT DETAILS"
        }
    ]
}
"@

# Main process
try {
    # Removing built-in Teams client
    $isTeamsInstalled = Get-AppxPackage -Name "MicrosoftTeams"
    if (-NOT[string]::IsNullOrEmpty($isTeamsInstalled)) {
        Remove-AppxPackage -Package $isTeamsInstalled.PackageFullName -ErrorAction Stop
    }
    # Removing chat icon
    $chatIconPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat"
    if (-NOT(Test-Path -Path $chatIconPath)) {
        New-Item -Path $chatIconPath -Force
    }
    if (Test-Path -Path $chatIconPath) {
        New-ItemProperty -Path $chatIconPath -Name "ChatIcon" -Value 2 -PropertyType "DWORD" -Force
    }

    # Escrow BitLocker recovery keys to Azure AD
    if ($bitLockerRecoveryKeystoAAD -eq $true) {
    $BitLockerVolume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        if (-NOT[string]::IsNullOrEmpty($BitLockerVolume)) {
            $KeyProtector = $BitLockerVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
            BackupToAAD-BitLockerKeyProtector -MountPoint $env:SystemDrive -KeyProtectorId $KeyProtector.KeyProtectorId -ErrorAction SilentlyContinue
        }
    }
    # Write success to registry
    New-ItemProperty -Path $registryPath -Name "SetupCompletecmd" -Value 0 -PropertyType String -Force
}
catch {
    # Write failure to registry
    New-ItemProperty -Path $registryPath -Name "SetupCompletecmd" -Value 1 -PropertyType String -Force
}
finally {
    if ($sendStatusTeams -eq $true) {
        Invoke-RestMethod -uri $webhookUri -Method Post -body $body -ContentType 'application/json'
    }
}
'@
            if (-NOT[string]::IsNullOrEmpty($Script)) {
                Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
            }
            # Do not run another type; break
            Break
        }
        PostRollBack {
            # CMD file
            $CMDFileName = $Type + '.cmd'
            $CMDFilePath = $Path + '\' + $CMDFileName
            New-item -Path $Path -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
            $GetCustomScriptPath = $PathInfo.FullName
            [String]$Script = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -WindowStyle Hidden -File `"$global:featureUpdateFolder\PostRollBack.ps1`""
            if (-NOT[string]::IsNullOrEmpty($Script)) {
                Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
            }
 
            # PS1 file
            $PS1FileName = $Type + '.ps1'
            $PS1FilePath = $Path + '\' + $PS1FileName
            New-item -Path $Path -Name $PS1FileName -Force -OutVariable PathInfo | Out-Null
            $GetCustomScriptPath = $PathInfo.FullName
            [String]$Script = @'
# Script goes here

.SYNOPSIS
    PostRollBack.ps1 file located in ProgramData\FeatureUpdates. Will be initiated by PostRollBack.cmd referenced by SetupConfig.ini
   
.DESCRIPTION
    Same as above

.NOTES
    Filename: PostRollBack.ps1
    Version: 3.0
    Author: Martin Bengtsson
    Blog: www.imab.dk
    Twitter: @mwbengtsson
#>

# Variables
$companyName = "imab.dk"
$targetWindowsBuild = "21H2"
$registryPath = "HKLM:\SOFTWARE\$companyName\WaaS\$targetWindowsBuild"
$runDateTime = Get-Date -Format g

# Teams message card variables
$sendStatusTeams = $true
$webhookUri = "<INSERT WEBHOOKE URI>"
$computerName = (Get-WmiObject -Class Win32_ComputerSystem).Name
$computerMake = (Get-WmiObject -Class Win32_BIOS).Manufacturer
$computerModel = (Get-WmiObject -Class Win32_ComputerSystem).Model
$ipAddress = (Get-WmiObject win32_Networkadapterconfiguration | Where-Object{ $_.ipaddress -notlike $null }).IPaddress | Select-Object -First 1
$body = @"
{
    "@type": "MessageCard",
    "@context": "https://schema.org/extensions",
    "summary": "WaaS Monitoring",
    "themeColor": "f07f13",
    "title": "Upgrade of $($computerName): FAILURE!",
    "sections": [
     {
            "activityTitle": "Kromann Reumert OSD",
            "activitySubtitle": "Windows 11 v21H2 Feature Update",
            "activityImage": "https://github.com/imabdk/Images/blob/main/failure.png?raw=true",
            "activityText": "",
            
            "facts": [
                {
                    "name": "Computername:",
                    "value": "$computerName"
                },
                {
                    "name": "Run date/time:",
                    "value": "$runDateTime"
                },
                {
                    "name": "IP address:",
                    "value": "$ipAddress"
                },
                {
                    "name": "Manufacturer:",
                    "value": "$computerMake"
                },
                {
                    "name": "Model:",
                    "value": "$computerModel"
                }
            ],
            "text": "<h2 style=color:#f07f13;>DEPLOYMENT DETAILS"
        }
    ]
}
"@

# Main process
try {
    # Write success to registry
    New-ItemProperty -Path $registryPath -Name "PostRollBackcmd" -Value 0 -PropertyType String -Force
}
catch {
    # Write failure to registry
    New-ItemProperty -Path $registryPath -Name "PostRollBackcmd" -Value 1 -PropertyType String -Force
}
finally {
    if ($sendStatusTeams -eq $true) {
        Invoke-RestMethod -uri $webhookUri -Method Post -body $body -ContentType 'application/json'
    }
}
'@
            if (-NOT[string]::IsNullOrEmpty($Script)) {
                Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
            }
            # Do not run another type; break
            Break
        }
    }
}
function Create-SetupConfigIni() {
    Write-Verbose -Verbose -Message "Running Create-SetupConfigIni function"
    [String]$iniFileContent = @'
[SetupConfig]
BitLocker=AlwaysSuspend
Compat=IgnoreWarning
Priority=Normal
DynamicUpdate=Disable
ShowOobe=None
Telemetry=Enable
POSTOOBE=C:\ProgramData\FeatureUpdates\SetupComplete.cmd
PostRollBack=C:\ProgramData\FeatureUpdates\PostRollBack.cmd
PostRollBackContext=System
'@
    if (Test-Path -Path $iniFileFolderPath) {
        $iniFileContent | Out-File -FilePath $iniFilePath -Encoding ASCII -Force
    }
    else {
        Write-Verbose -Verbose -Message "Path to SetupConfig.ini file does not exist: $iniFileFolderPath"
    }
}
# Main process
try {
    Write-Verbose -Verbose -Message "Running Feature Updates script. Creating folders, scripts and SetupConfig.ini"
    Create-FeatureUpdatesFolders
    Create-CustomActionScript SetupComplete
    Create-CustomActionScript PostRollBack
    Create-SetupConfigIni
}
catch {
    Write-Verbose -Verbose -Message "Feature Updates script failed to run properly. Please investigate"
    exit 1
}
finally {
    Write-Verbose -Verbose -Message "Feature Updates script is done running"
    exit 0
}
