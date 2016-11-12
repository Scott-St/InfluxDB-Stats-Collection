# Powershell to write to DB Script
# Task Scheduler to execute this task every 30 minutes
#
# Scott Stevenson
# 
# Created: 23-10-2016
# Modified: 12-11-2016
#

$ComputerSystem = Get-WmiObject -class Win32_ComputerSystem | Select Name
$Device = $ComputerSystem.name

$uri = 'http://192.168.254.3:8086/write?db=statistics&precision=s'
$authheader = "Basic " + ([Convert]::ToBase64String([System.Text.encoding]::ASCII.GetBytes("datauser:password")))

# Location of the AIDA64 registry information
$key = 'HKCU:\Software\FinalWire\AIDA64\SensorValues'
	
# Unix epoch date in seconds
$CURDATE=[int][double](Get-Date(Get-Date).ToUniversalTime()-uformat "%s")


#
# Disk Drives Space from WMI/S.M.A.R.T.
#
$Interested =@("_TOTAL","C:","D:","E:","F:","S:")

$Disks = Get-WmiObject -class Win32_PerfFormattedData_PerfDisk_LogicalDisk | where { $Interested -contains $_.Name} | Select FreeMegabytes,PercentFreeSpace,Name
Foreach($Disk in $Disks) { 

    # Special case for D: as its a Windows Storage Spaces disk with 2 physical disks.
    # Only reading the one -- sde
    # The other is sdd
    if ($Disk -like "*D:*") {
        $PowerOnHours = & 'C:\Program Files\smartmontools\bin\smartctl.exe' -n standby -A /dev/sde | Select-String -Pattern "Power_On_Hours"
    } else {
	    $PowerOnHours = & 'C:\Program Files\smartmontools\bin\smartctl.exe' -n standby -A $Disk.Name | Select-String -Pattern "Power_On_Hours"
	}
    
	# Special Case for my SSD as it lists the mins/seconds also.
	# leftpart is everything  before the h which roughly matches the others but not quite.

	$pos = $PowerOnHours.line.IndexOf("h")
	if ($pos -gt 0) {
		$leftPart = $PowerOnHours.line.Substring(0, $pos)
		$arrPowerOnHours = $leftPart -split '       '
		$PowerOnHours = $arrPowerOnHours[2]
	}
	else {
		$leftPart = $PowerOnHours
		$arrPowerOnHours = $leftPart -split '       '
		$PowerOnHours = $arrPowerOnHours[3]
	}
	
	$FreeMegabytes = $Disk.FreeMegabytes
	$PercentFreeSpace = $Disk.PercentFreeSpace
	$PercentUsedSpace = 100 - $Disk.PercentFreeSpace
	$UsedMegaBytes = [int]($FreeMegabytes / (0.01 * $PercentFreeSpace)) - $FreeMegabytes
	
	# Remove : from the disk letter
	$DiskName = $Disk.Name
	$DiskName = $Disk.Name -replace ":.*"
	
    if ($Disk -like "*_Total*") {
        # If its the total, only enter the space not the Power On Hours as this doesnt make sense.
        # Do Nothing Here
    } else {
	    $postParams = "diskPowerOnHours,DEVICE=$Device,DISK=$DiskName PowerOnHours=$PowerOnHours $CURDATE"
	    Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams
    }
    $postParams = "drive_spaceStats,Device=$Device,Drive=$DiskName Free=$FreeMegabytes,Used=$UsedMegaBytes,Utilization=$PercentUsedSpace $CURDATE"
	Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams
}


#
# Uptime from WMI
#
$os = Get-WmiObject win32_operatingsystem
$uptime = (Get-Date) - ($os.ConvertToDateTime($os.lastbootuptime))
$uptimeS = [math]::Round($uptime.TotalSeconds)

$postParams = "uptime,Device=$Device Uptime=$uptimeS $CURDATE"
Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams

exit