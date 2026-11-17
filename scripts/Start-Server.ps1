# Starts llama-server (if it is not running) and lists the model profiles it offers.
# Models are loaded on first use, not at start.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Start-Server.ps1

. "$PSScriptRoot\_common.ps1"

Start-Server
"llama-server is running at $((Get-ServerConfig).baseUrl)  (log: $((Get-ServerConfig).logFile))"
Get-ServerModels | Format-Table -AutoSize
