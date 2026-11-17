# Stops llama-server and with it all loaded models. Frees the GPU memory.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Stop-Server.ps1

. "$PSScriptRoot\_common.ps1"

Stop-Server
'llama-server stopped.'
