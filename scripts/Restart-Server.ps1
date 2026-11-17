# Restarts llama-server. Needed after every change to config\server.json or
# config\models.json: the server reads them only at start.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Restart-Server.ps1

. "$PSScriptRoot\_common.ps1"

Stop-Server
Start-Server
"llama-server is running at $((Get-ServerConfig).baseUrl)  (log: $((Get-ServerConfig).logFile))"
Get-ServerModels | Format-Table -AutoSize
