# 1. Stop the automation task so it doesn't keep reviving the process
Stop-ScheduledTask -TaskName "AzurePersistentServer" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "AzurePersistentServer" -Confirm:$false -ErrorAction SilentlyContinue

# 2. Kill any PowerShell processes that might be running the web server hidden
Get-Process -Name "PowerShell" | Where-Object { $_.Id -ne $PID } | Stop-Process -Force -ErrorAction SilentlyContinue

# 3. Clean up the URL reservations (Ignoring errors if they don't exist)
netsh http delete urlacl url=http://*:8080/ 2>$null
netsh http delete urlacl url=http://+:8080/ 2>$null

# 4. Force a reset of the network stack for Port 8080
# This effectively tells the kernel (PID 4) to drop those hanging connections
Stop-Service -Name W3SVC -ErrorAction SilentlyContinue
Start-Service -Name W3SVC -ErrorAction SilentlyContinue

Write-Host "Cleanup complete. If Process 4 still shows 'TimeWait', it will disappear automatically in ~60 seconds." -ForegroundColor Cyan