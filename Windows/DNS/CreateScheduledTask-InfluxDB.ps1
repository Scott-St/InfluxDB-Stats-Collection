# Creates a new scheduled task each time the PC is booted.
# New task will start 1 min after the task is created.
# This makes sure the task will run ON THE MINUTE instead of just a random time.
#
# Scott Stevenson
# Created: 23-10-2016
# Modified: 28-10-2016
#

#
# Global Variables
#
$TaskPath = "User Created Tasks\"
$User = ''
$password = ''


#
# Creates a task that executes every 1 minute on the :00
#
$TaskName = "InfluxDB-Statistics-1m"
$STSet = New-ScheduledTaskSettingsSet -Priority 4
$PS = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument 'C:\Scripts\InfluxDB-DataCollection-1m.ps1'
$Time = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(+1).ToString('HH:mm')  `
    -RepetitionInterval (New-TimeSpan -Minutes 1)

# Delete existing task (seems easier then checking to see if it exists and then modifying the start time.)
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

# Seems dumb that to delete a task it uses the name only but to create one it needs the path + name
$TaskName = $TaskPath + $TaskName

# Register new scheduled task
Register-ScheduledTask -Action $PS -Trigger $Time -TaskName $TaskName -User $User -Password $password -Settings $STSet


#
# Creates a task that executes every 1 minute on the :30
# If you want to excute the same task every 30 seconds it needs to be in the :00 and the :00 script.
#
$date = (Get-Date)
$seconds=$date.second

if ($seconds -gt 30)
{
	$secondsAdd = (60 - $seconds) + 30
}
else
{
	$secondsAdd = 30 - $seconds
}

$TaskName = "InfluxDB-Statistics-30s"
$STSet = New-ScheduledTaskSettingsSet -Priority 4
$PS = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument 'C:\Scripts\InfluxDB-DataCollection-CPU-30s.ps1'
$Time = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(+1).AddSeconds($secondsAdd).ToString('HH:mm:ss')  `
    -RepetitionInterval (New-TimeSpan -Minutes 1)

# Delete existing task (seems easier then checking to see if it exists and then modifying the start time.)
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

# Seems dumb that to delete a task it uses the name only but to create one it needs the path + name
$TaskName = $TaskPath + $TaskName

# Register new scheduled task
Register-ScheduledTask -Action $PS -Trigger $Time -TaskName $TaskName -User $User -Password $password -Settings $STSet


#
# Creates a task that executes every 30 minute
#
$TaskName = "InfluxDB-Statistics-30m"
$STSet = New-ScheduledTaskSettingsSet -Priority 4
$PS = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument 'C:\Scripts\InfluxDB-DataCollection-30m.ps1'
$Time = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(+1).ToString('HH:mm')  `
    -RepetitionInterval (New-TimeSpan -Minutes 30)

# Delete existing task (seems easier then checking to see if it exists and then modifying the start time.)
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

# Seems dumb that to delete a task it uses the name only but to create one it needs the path + name
$TaskName = $TaskPath + $TaskName

# Register new scheduled task
Register-ScheduledTask -Action $PS -Trigger $Time -TaskName $TaskName -User $User -Password $password -Settings $STSet
