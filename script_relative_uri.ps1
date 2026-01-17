# 1. Setup Directories
$scriptDir = "C:\AzureScripts"
if (!(Test-Path $scriptDir)) { New-Item -ItemType Directory -Path $scriptDir -Force }
$scriptPath = "$scriptDir\PersistentServer8080.ps1"

# 2. Open Firewall Port
New-NetFirewallRule -DisplayName "Allow HTTP 8080" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue

# 3. Create the background server script file
# We use a single-quoted string here to prevent PowerShell from trying to execute variables now
$serverCode = @'
$port = 8080
# Clear existing processes on this port
Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | ForEach-Object { 
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue 
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://*:$port/")
$listener.Start()

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        $relativePath = $request.Url.PathAndQuery
        $machineName = $env:COMPUTERNAME
        $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime.ToString("yyyy-MM-dd HH:mm:ss")
        $currentTime = Get-Date -Format "HH:mm:ss"

        $html = @"
        <html>
        <head>
            <style>
                body { font-family: 'Segoe UI', sans-serif; background: #010409; color: #e6edf3; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                .card { border: 1px solid #30363d; padding: 40px; border-radius: 12px; background: #0d1117; width: 450px; box-shadow: 0 8px 24px rgba(0,0,0,0.5); text-align: center; }
                .header { color: #238636; font-size: 0.75rem; font-weight: bold; text-transform: uppercase; margin-bottom: 20px; }
                .label { color: #8b949e; font-size: 0.7rem; text-transform: uppercase; margin-top: 15px; }
                .value { font-size: 1.1rem; font-weight: 600; color: #58a6ff; font-family: 'Consolas', monospace; }
                .path-box { background: #161b22; padding: 15px; border-radius: 6px; border: 1px solid #30363d; margin-top: 10px; color: #7ee787; font-size: 1.5rem; word-break: break-all; }
            </style>
        </head>
        <body>
            <div class='card'>
                <div class='header'>System Online</div>
                <div class='label'>Machine Name</div><div class='value'>$machineName</div>
                <div class='label'>Last System Boot</div><div class='value'>$bootTime</div>
                <div class='label'>Relative Path</div>
                <div class='path-box'>$relativePath</div>
                <div style='margin-top:20px; font-size:0.7rem; color:#484f58;'>Server Time: $currentTime</div>
            </div>
        </body>
        </html>
"@
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $response.ContentType = "text/html"
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    } catch { }
}
'@

$serverCode | Out-File -FilePath $scriptPath -Encoding UTF8 -Force

# 4. Create and Register the Scheduled Task
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File $scriptPath"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Clean up old task if it exists
Unregister-ScheduledTask -TaskName "AzurePersistentServer" -Confirm:$false -ErrorAction SilentlyContinue

# Register the new one
Register-ScheduledTask -TaskName "AzurePersistentServer" -Action $action -Trigger $trigger -Principal $principal

# 5. Start the task immediately
Start-ScheduledTask -TaskName "AzurePersistentServer"

Write-Host "Done! The server is now running and scheduled for every boot."