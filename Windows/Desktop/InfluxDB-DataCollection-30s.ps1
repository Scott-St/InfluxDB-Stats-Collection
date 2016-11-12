# Powershell to write to DB Script
# Task Scheduler to execute this task each minute on the 30s
# Used to compliment the 1minute task for some metrics I want to collect more frequently
#
# Scott Stevenson
# 
# Created: 23-10-2016
# Modified: 12-11-2016
#

# Include influxDB information
. .\InfluxDB-Connection.ps1

$ComputerSystem = Get-WmiObject -class Win32_ComputerSystem | Select Name,NumberOfLogicalProcessors
$Device = $ComputerSystem.name

$uri = "$server/write?db=$database&precision=s"
$authheader = "Basic " + ([Convert]::ToBase64String([System.Text.encoding]::ASCII.GetBytes($username + ":" + $password))))

# Location of the AIDA64 registry information
$key = 'HKCU:\Software\FinalWire\AIDA64\SensorValues'
	
# Unix epoch date in seconds
$CURDATE=[int][double](Get-Date(Get-Date).ToUniversalTime()-uformat "%s")


#
# CPU Metrics from AIDA64/WMI
#

# Number of CPU cores
$numCores = $ComputerSystem.NumberOfLogicalProcessors

$CPUClock = Get-ItemPropertyValue $key 'Value.SCPUCLK'

# Some specific core stats from WMI
# Not interested in the totals for now
$notInterested =@("0,_TOTAL")

$CPUs = Get-WMIObject -class Win32_PerfFormattedData_Counters_ProcessorInformation | where { $notInterested -notcontains $_.Name} | Select Name,PercentUserTime,PercentPrivilegedTime,PercentProcessorTime
Foreach($CPU in $CPUs) { 
	$PercentUserTime = $CPU.PercentUserTime
	$PercentPrivilegedTime = $CPU.PercentPrivilegedTime
	$PercentProcessorTime = $CPU.PercentProcessorTime
	
	$Name = $CPU.Name -replace "0,",""
	
	$postParams = "cpuStats,Device=$Device,Core=$Name CPUusr=$PercentUserTime,CPUsys=$PercentPrivilegedTime,CPUUtilization=$PercentProcessorTime,CPUClock=$CPUClock $CURDATE"
	Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams
}


#
#  Hard Disk Metrics from WMI
#
$uri = 'http://192.168.254.3:8086/write?db=statistics&precision=s'
$Interested =@("_TOTAL","C:","D:","E:","F:","S:")
$Disks = Get-WmiObject -class Win32_PerfFormattedData_PerfDisk_LogicalDisk | where { $Interested -contains $_.Name} | Select CurrentDiskQueueLength,DiskBytesPersec,DiskReadBytesPersec,DiskWriteBytesPersec,PercentDiskTime,Name

Foreach($Disk in $Disks) { 
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
}

	
#
# EXIT
#
exit