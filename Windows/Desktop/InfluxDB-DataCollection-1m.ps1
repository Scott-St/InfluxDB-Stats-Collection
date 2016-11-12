# Powershell to write to DB Script
# Task Scheduler to execute this task each minute
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
$CPUtemp = Get-ItemPropertyValue $key 'Value.TCPU'

# Main CPU Temperature
$postParams = "CPUtempStats,Device=$Device,Core=_TOTAL Temperature=$CPUtemp $CURDATE"
Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams

# Add in all the core temperatures
$core = 0
while($core -ne $numCores)
{
	$subkey = 'Value.TCC-1-' + ($core + 1)
	$coretemp = Get-ItemPropertyValue $key $subkey
	$postParams = "CPUtempStats,Device=$Device,Core=$core Temperature=$coretemp $CURDATE"
	Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams
	$core++
}

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
# Network Stats from WMI
#
$tmpfile = $Env:Temp + "\influxDB-Stats-Tcpip_NetworkInterface.xml"

# Get current interface stats
$Tcpip_Current = Get-WmiObject -class Win32_PerfRawData_Tcpip_NetworkInterface | where{$_.Name -eq "Intel[R] Ethernet Connection [2] I218-V"} | Select BytesReceivedPersec,BytesSentPersec,Name

# See if there is an existing tempory file to compare to
If (Test-Path $tmpfile){
  # If the file exists then read it and get the difference
  
  $Tcpip_Last = Import-CliXml $tmpfile
  
  # Subtract current vs last bytes
  $bytesIn = $Tcpip_Current.BytesReceivedPersec - $Tcpip_Last.BytesReceivedPersec
  $bytesOut = $Tcpip_Current.BytesSentPersec - $Tcpip_Last.BytesSentPersec
  
  # If the counter resets then dont record negative bytes
  if ($bytesIn -le 0) {
	$bytesIn = 0
  }
  if ($bytesOut -le 0) {
	$bytesOut = 0
  }
    
}Else{
  # If no file exists already then create it and set the in/out bytes to 0
  $bytesIn = 0
  $bytesOut = 0
  }

# Export the current data to the tempory file
$Tcpip_Current | Export-CliXml $tmpfile

# Name of the network adapter
$interface = ($Tcpip_Current.Name)

#replace any spaces with _ so influxdb doesnt barf.
$interface = $interface.replace(' ','_')

$postParams = "interfaceStats,Interface=$interface,Device=$Device bytesIn=$bytesIn,bytesOut=$bytesOut $CURDATE"
Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams


#
#  Hard Disk Metrics from WMI
#
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
# GPU Metrics from AIDA64
#
$GPUDiode = Get-ItemPropertyValue $key 'Value.TGPU1DIO'
$GPUUtil = Get-ItemPropertyValue $key 'Value.SGPU1UTI'
$GPUClock = Get-ItemPropertyValue $key 'Value.SGPU1CLK'

$postParams = "GPUstats,Device=$Device GPUClock=$GPUClock,GPUUtilization=$GPUUtil,GPUTemp=$GPUDiode $CURDATE"
Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams


#
# Memory Metrics from WMI
#
$OperatingSystem = Get-WmiObject -class Win32_OperatingSystem | Select FreePhysicalMemory

$memTotal = $ComputerSystem.TotalPhysicalMemory

# Returns Kb of memory instead of bytes
$memFree = $OperatingSystem.FreePhysicalMemory * 1024

$memUsed = $memTotal - $memFree

$postParams = "memoryStats,Device=$Device memFree=$memFree,memUsed=$memUsed $CURDATE"
Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams

#
# EXIT
#
exit