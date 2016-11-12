# Powershell to write to DB Script
#
# Scott Stevenson
#
# Created: 23-10-2016
# Modified: 12-11-2016
#

#
# Include influxDB information
#
. "$PSScriptRoot\InfluxDB-Connection.ps1"

$ComputerSystem = Get-WmiObject -class Win32_ComputerSystem | Select Name,NumberOfLogicalProcessors,TotalPhysicalMemory
$Device = $ComputerSystem.name

$uri = "$server/write?db=$database&precision=s"
$authheader = "Basic " + ([Convert]::ToBase64String([System.Text.encoding]::ASCII.GetBytes($username + ":" + $password)))
	
# Unix epoch date in seconds
$CURDATE=[int][double](Get-Date(Get-Date).ToUniversalTime()-uformat "%s")

#
# CPU Metrics from WMI
#

# Some specific core stats from WMI
# Not interested in the totals for now
$notInterested =@("_TOTAL","0,_TOTAL")

# Reset variable
$core=0

$CPUs = Get-WMIObject -class Win32_PerfFormattedData_Counters_ProcessorInformation | where { $notInterested -notcontains $_.Name} | Select Name,PercentUserTime,PercentPrivilegedTime,PercentProcessorTime
Foreach($CPU in $CPUs) { 
	$PercentUserTime = $CPU.PercentUserTime
	$PercentPrivilegedTime = $CPU.PercentPrivilegedTime
	$PercentProcessorTime = $CPU.PercentProcessorTime
	
	$postParams = "cpuStats,Device=$Device,Core=$core CPUusr=$PercentUserTime,CPUsys=$PercentPrivilegedTime,CPUUtilization=$PercentProcessorTime $CURDATE"
	Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams
	
	$core++
	}


#
#  Hard Disk Metrics from WMI
#
$Disk = Get-WmiObject -class Win32_PerfFormattedData_PerfDisk_LogicalDisk | where{$_.Name -eq "C:"} | Select CurrentDiskQueueLength,DiskBytesPersec,DiskReadBytesPersec,DiskWriteBytesPersec,PercentDiskTime,Name

# Remove : from the disk letter
$DiskName=$Disk.Name
$DiskName= $Disk.Name -replace ":.*"

# Assign variables to the objects. It doesnt work to put the objects directly into the params string.  Maybe a way around it but this is easy.
$DiskQueueLength = $Disk.CurrentDiskQueueLength
$DiskBytesPersec = $Disk.DiskBytesPersec
$DiskReadBytesPersec = $Disk.DiskReadBytesPersec
$DiskWriteBytesPersec = $Disk.DiskWriteBytesPersec
$PercentDiskTime = $Disk.PercentDiskTime
 
$postParams = "diskStats,Disk=$DiskName,Device=$Device QueueLength=$DiskQueueLength,BytesPersec=$DiskBytesPersec,ReadBytesPersec=$DiskReadBytesPersec,WriteBytesPersec=$DiskWriteBytesPersec,Utilization=$PercentDiskTime $CURDATE"
Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams

#
# EXIT
#
exit