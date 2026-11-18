# Prints the greeting from config\settings.json. Placeholder of the project template:
# replace it with the first real script.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Show-Settings.ps1

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Config.ps1"

(Get-Settings).greeting
