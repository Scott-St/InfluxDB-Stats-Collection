# Powershell to write to DB Script
#
# Scott Stevenson
# Created: 23-10-2016
# Modified: 29-10-2016
#

$ComputerSystem = Get-WmiObject -class Win32_ComputerSystem | Select Name,NumberOfLogicalProcessors,TotalPhysicalMemory
$Device = $ComputerSystem.name

$uri = 'http://192.168.254.3:8086/write?db=statistics&precision=s'
$authheader = "Basic " + ([Convert]::ToBase64String([System.Text.encoding]::ASCII.GetBytes("datauser:password")))

# Unix epoch date in seconds
$CURDATE=[int][double](Get-Date(Get-Date).ToUniversalTime()-uformat "%s")

#
# Disk Drives Space from WMI
#
$Interested =@("_TOTAL","C:")

$Disks = Get-WmiObject -class Win32_PerfFormattedData_PerfDisk_LogicalDisk | where { $Interested -contains $_.Name} | Select FreeMegabytes,PercentFreeSpace,Name
Foreach($Disk in $Disks) { 
	$FreeMegabytes = $Disk.FreeMegabytes
	$PercentFreeSpace = $Disk.PercentFreeSpace
	$PercentUsedSpace = 100 - $Disk.PercentFreeSpace
	$UsedMegaBytes = [int]($FreeMegabytes / (0.01 * $PercentFreeSpace)) - $FreeMegabytes
	
	# Remove : from the disk letter
	$DiskName=$Disk.Name
	$DiskName= $Disk.Name -replace ":.*"
	
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