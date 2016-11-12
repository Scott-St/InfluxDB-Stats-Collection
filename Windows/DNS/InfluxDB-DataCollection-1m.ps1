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

# Location of the AIDA64 registry information
#$key = 'HKCU:\Software\FinalWire\AIDA64\SensorValues'
	
# Unix epoch date in seconds
$CURDATE=[int][double](Get-Date(Get-Date).ToUniversalTime()-uformat "%s")


#
# Network Stats from WMI
#
$tmpfile = $Env:Temp + "\influxDB-Stats-Tcpip_NetworkInterface.xml"

# Get current interface stats
$Tcpip_Current = Get-WmiObject -class Win32_PerfRawData_Tcpip_NetworkInterface | where{$_.Name -eq "Intel[R] 82574L Gigabit Network Connection"} | Select BytesReceivedPersec,BytesSentPersec,Name

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
# DNS Query Stats
#
$tmpfile = $Env:Temp + "\influxDB-Stats-DNS.xml"

# Get current interface stats
$DNS_Current = Get-WmiObject -class Win32_PerfFormattedData_DNS_DNS | Select TotalQueryReceived,RecursiveQueries

# See if there is an existing tempory file to compare to
If (Test-Path $tmpfile){
  # If the file exists then read it and get the difference
  
  $DNS_Last = Import-CliXml $tmpfile
  
  # Subtract current vs last query numbers
  $totalQueries = $DNS_Current.TotalQueryReceived - $DNS_Last.TotalQueryReceived
  $recursiveQueries = $DNS_Current.RecursiveQueries - $DNS_Last.RecursiveQueries
  
  # If the counter resets then dont record negative bytes
  if ($totalQueries -le 0) {
	$totalQueries = 0
  }
  if ($recursiveQueries -le 0) {
	$recursiveQueries = 0
  }
    
}Else{
  # If no file exists already then create it and set the totals to 0
  $totalQueries = 0
  $recursiveQueries = 0
  }

# Export the current data to the tempory file
$DNS_Current | Export-CliXml $tmpfile

$postParams = "DNSStats,Device=$Device TotalQueryReceived=$totalQueries,RecursiveQueries=$recursiveQueries $CURDATE"
Invoke-RestMethod -Headers @{Authorization=$authheader} -Uri $uri -Method POST -Body $postParams


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