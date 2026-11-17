# Reads the settings of the project from config\settings.json. Every script gets its
# settings through Get-Settings, so no script contains fixed values of its own.

$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Get-Settings([string]$Path = (Join-Path $script:ProjectRoot 'config\settings.json')) {
    # Returns the settings as an object. Throws with a clear message if the file is
    # missing or not valid JSON.
    if (-not (Test-Path $Path)) { throw "Settings file not found: $Path" }
    try {
        return (Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        throw "Settings file is not valid JSON: $Path"
    }
}
