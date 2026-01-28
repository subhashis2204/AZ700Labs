# ==============================================================================
# PHASE 1: DEEP CLEAN & PREPARATION
# ==============================================================================
Write-Host "🧹 Cleaning environment..." -ForegroundColor Yellow
Get-Process -Name "PowerShell" | Where-Object { $_.Id -ne $PID } | Stop-Process -Force -ErrorAction SilentlyContinue
netsh http delete urlacl url=http://*:80/ 2>$null
netsh http add urlacl url=http://*:80/ user=Everyone 2>$null
New-NetFirewallRule -DisplayName "Allow HTTP 80" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue

# ==============================================================================
# PHASE 2: SETUP DIRECTORIES AND SERVER SCRIPT
# ==============================================================================
$scriptDir = "C:\AzureScripts"
if (!(Test-Path $scriptDir)) { New-Item -ItemType Directory -Path $scriptDir -Force }
$scriptPath = "$scriptDir\PersistentServer80.ps1"

$serverCode = @'
$port = 80
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
        $relativePath = $request.Url.AbsolutePath

        # ==========================================
        # ROUTE: /health (For Custom Health Probe)
        # ==========================================
        if ($relativePath -eq "/health") {
            $msg = "OK"
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($msg)
            $response.ContentLength64 = $buffer.Length
            $response.ContentType = "text/plain"
            $response.StatusCode = 200
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
            continue # Skip the rest and wait for next request
        }

        # ==========================================
        # ROUTE: Default (Dashboard)
        # ==========================================
        $rawQuery    = $request.Url.Query
        $queryString = if ([string]::IsNullOrWhiteSpace($rawQuery)) { "(No Parameters)" } else { $rawQuery }
        $machineName = $env:COMPUTERNAME
        $bootTime    = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString("yyyy-MM-dd HH:mm:ss")
        $currentTime = Get-Date -Format "HH:mm:ss"

        $html = @"
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #010409; color: #e6edf3; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { border: 1px solid #30363d; padding: 40px; border-radius: 12px; background: #0d1117; width: 520px; box-shadow: 0 8px 24px rgba(0,0,0,0.5); text-align: center; }
        .header { color: #238636; font-size: 0.75rem; font-weight: bold; text-transform: uppercase; margin-bottom: 20px; letter-spacing: 1px; }
        .label { color: #8b949e; font-size: 0.7rem; text-transform: uppercase; margin-top: 18px; }
        .value { font-size: 1.1rem; font-weight: 600; color: #58a6ff; font-family: Consolas, monospace; }
        .path-box { background: #161b22; padding: 15px; border-radius: 6px; border: 1px solid #30363d; margin-top: 8px; color: #7ee787; font-size: 1.1rem; word-break: break-all; }
        .query-box { background: #1c2128; padding: 15px; border-radius: 6px; border: 1px solid #444c56; margin-top: 8px; color: #d2a8ff; font-size: 1rem; font-family: Consolas, monospace; word-break: break-all; }
        .footer { margin-top: 25px; font-size: 0.7rem; color: #484f58; }
    </style>
</head>
<body>
    <div class="card">
        <div class="header">Azure Backend Online</div>
        <div class="label">Machine Name</div><div class="value">$machineName</div>
        <div class="label">Last System Boot</div><div class="value">$bootTime</div>
        <div class="label">Relative Path</div><div class="path-box">$relativePath</div>
        <div class="label">Query String Received</div><div class="query-box">$queryString</div>
        <div class="footer">Server Time: $currentTime</div>
        <div style="margin-top:10px; color:#238636; font-size:0.7rem;">Health Route /health is Active</div>
    </div>
</body>
</html>
"@
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $response.ContentType = "text/html"
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close() 
    }
    catch { }
}
'@

$serverCode | Out-File -FilePath $scriptPath -Encoding UTF8 -Force

# ==============================================================================
# PHASE 3: REGISTER AND START
# ==============================================================================
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Unregister-ScheduledTask -TaskName "AzurePersistentServer" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "AzurePersistentServer" -Action $action -Trigger $trigger -Principal $principal
Start-ScheduledTask -TaskName "AzurePersistentServer"

Write-Host "✅ Done! Use /health for your Custom Health Probe path." -ForegroundColor Green