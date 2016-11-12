# InfluxDB-Stats-Collection
Scripts I am using on my network to collect data for InfluxDB.  
These are specific to my network but in case anyone wants to disect them, feel free.

- Ensure you change the username/password in the scripts.  This is just a default.  It is not required by default on InfluxDB.
- Change the path to your InfluxDB server.

###Scripts for:
- unRAID
- Windows Server DNS
- Windows PCs
- DD-WRT Router

###Windows
Edit **TaskScheduler-Vars.ps1** to set the variables for creating a scheduled task.

Run **CreateScheduledTask-InfluxDB.ps1** with Powershell to automatically create scheduled tasks. Alternatively, create a scheduled task that will run on startup to create/re-create the scheduled taskes using the action:

```
Powershell.exe "C:\Path\To\CreateScheduledTask-InfluxDB.ps1"
```

This will create 3 scheduled tasks for the 30 minute, 1 minute (:00) and 1 minute (:30).

Make sure to edit **InfluxDB-Connection.ps1** for the connection to InfluxDB.
