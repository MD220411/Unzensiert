# Starts Claude Code against the local llama.cpp server instead of the Anthropic cloud.
# The variables are set for this process only, so the normal `claude` command and the
# VS Code extension keep using your Anthropic account.
#
#   claude-local                     (uses "model" from config\agent.json)
#   claude-local -Model schnell      (short name from config\agent.json, or a profile name
#                                     from config\models.json)
#   claude-local -OnExit keep        (overrides "onExit" from config\agent.json for this call)
#   claude-local -p "question"       (all other arguments go to Claude Code unchanged)
#   /model inside a session          (switch between the profiles listed under "picker")
#
# When the last session ends, the models are unloaded so the GPU memory is free again
# ("onExit" in config\agent.json, docs\agent.md).

# No param() block on purpose: PowerShell would try to bind Claude Code flags such as
# -p to its own parameters. Arguments are split by hand instead.
$Model = $null
$OnExit = $null
$ClaudeArgs = @()
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq '-Model' -and ($i + 1) -lt $args.Count) { $Model = $args[$i + 1]; $i++ }
    elseif ($args[$i] -eq '-OnExit' -and ($i + 1) -lt $args.Count) { $OnExit = $args[$i + 1]; $i++ }
    else { $ClaudeArgs += $args[$i] }
}

. "$PSScriptRoot\_common.ps1"

$agent = Get-AgentConfig
$server = Get-ServerConfig
$claude = Find-ClaudeCode
if (-not $claude) {
    [Console]::Error.WriteLine('claude-local: Claude Code is not installed. Run the installer again (Install.cmd in the claude-local folder) or see https://code.claude.com/docs/en/setup')
    exit 1
}
if ($Model) {
    $Model = Resolve-ModelName $Model
    $null = Get-ModelProfile $Model      # fails with a clear message if the profile is unknown
    if (-not (Test-ModelInstalled $Model)) {
        [Console]::Error.WriteLine("claude-local: the model '$Model' is not installed. Download it with: powershell -ExecutionPolicy Bypass -File `"$PSScriptRoot\Get-Model.ps1`" -Model $Model")
        exit 1
    }
} else {
    # "model" in config\agent.json, or the first installed model of the picker
    $Model = Get-DefaultAgentModel
    if (-not $Model) {
        [Console]::Error.WriteLine("claude-local: no model is installed yet. Run the installer: $(Join-Path $script:ProjectRoot 'Install.cmd')")
        exit 1
    }
}

if (-not (Test-ServerUp)) {
    'llama-server is not running, starting it ...'
    Start-Server
}

# --- connection ---------------------------------------------------------------------
# llama-server speaks the Anthropic Messages API at /v1/messages. Claude Code sends the
# token as "Authorization: Bearer"; it insists on a value even if the server asks for none.
$env:ANTHROPIC_BASE_URL = $server.baseUrl
$env:ANTHROPIC_AUTH_TOKEN = Get-ServerApiKey
if (-not $env:ANTHROPIC_AUTH_TOKEN) { $env:ANTHROPIC_AUTH_TOKEN = 'local' }
$env:ANTHROPIC_API_KEY = ''

# --- models -------------------------------------------------------------------------
# Claude Code uses a small model ("haiku") for background jobs. Point it and the built-in
# aliases at the start model: only one large model fits in VRAM. Subagents get no fixed
# model on purpose, so they follow the main model after a switch with /model.
$env:ANTHROPIC_MODEL = $Model
$env:ANTHROPIC_DEFAULT_OPUS_MODEL = $Model
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Model
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $Model
Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue

# --- settings for this launch only ----------------------------------------------------
# Everything below goes into a settings file that is handed over with --settings, so the
# normal `claude` command keeps its own picker, look and rules.
$pickerModels = @()
$extraArgs = @()
$settings = [ordered]@{}
# /model inside a session: offer the local profiles from config\agent.json ("picker")
# instead of the Anthropic models; only those whose model file is on this machine
if ($agent.picker) {
    $rows = @()
    foreach ($row in $agent.picker) {
        if (-not (Test-ModelInstalled ([string]$row.model))) { continue }
        $rows += [ordered]@{ model = [string]$row.model; label = [string]$row.label; description = [string]$row.description }
        $pickerModels += [string]$row.model
    }
    if ($rows.Count -gt 0) { $settings['modelPicker'] = [ordered]@{ options = $rows; replaceBuiltInOptions = $true } }
}
# the look of a local session: warm theme and status line with the graphics cards
# (lib\Style.ps1, docs\style.md); empty if the look is not installed
$look = Get-LocalLookSettings
foreach ($key in $look.Keys) { $settings[$key] = $look[$key] }
# the safety guard: checks every tool call of the model before it runs
# (lib\Safety.ps1, config\guard.json, docs\security.md); empty if switched off
Merge-Settings $settings (Get-SafetySettings)
# the closing check: runs the project's check command and reminds of tests and README when
# the model wants to end an answer in which it changed files (lib\Quality.ps1,
# "stopCheck" in config\agent.json, docs\agent.md); empty if switched off
Merge-Settings $settings (Get-QualitySettings)
if ($settings.Count -gt 0) {
    $settingsFile = Join-Path $env:TEMP 'claude-local-settings.json'
    # WriteAllText writes UTF-8 without BOM (Set-Content -Encoding utf8 would add one)
    [System.IO.File]::WriteAllText($settingsFile, ($settings | ConvertTo-Json -Depth 8))
    $extraArgs += @('--settings', $settingsFile)
}

# --- context window -----------------------------------------------------------------
# Claude Code does not know local model names and would assume a huge context window, so
# it would never compact the conversation in time. Tell it the real window: ctx-size of
# the profile, minus a safety margin because Claude Code only estimates how many tokens
# the local tokenizer produces. The value is fixed for the session, so with several
# models in the picker the smallest window counts.
$ctx = Get-ModelContextSize $Model
if ($ctx -le 0) {
    $ctx = [int]$agent.fallbackContextTokens
    "claude-local: WARNING - profile '$Model' sets no ctx-size in config\models.json. Assuming $ctx tokens."
}
foreach ($other in $pickerModels) {
    $otherCtx = Get-ModelContextSize $other
    if ($otherCtx -gt 0 -and $otherCtx -lt $ctx) { $ctx = $otherCtx }
}
$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = [string][int]($ctx * [double]$agent.contextSafetyFactor)
$env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = [string]$agent.maxOutputTokens

# --- working rules for the local model ------------------------------------------------
# Appended to Claude Code's system prompt in every session (docs\agent.md).
if ($agent.rulesFile) {
    $rulesFile = Join-Path $script:ConfigDir ([string]$agent.rulesFile)
    if (Test-Path $rulesFile) { $extraArgs += @('--append-system-prompt-file', $rulesFile) }
    else { "claude-local: WARNING - rules file $rulesFile not found, starting without it." }
}

# --- fixed procedures ---------------------------------------------------------------------
# /feature, /bugfix and /review: commands in config\workflows, loaded for this launch only
# so that the normal `claude` does not get them (docs\agent.md).
$pluginDir = Get-PluginDir
if ($pluginDir) { $extraArgs += @('--plugin-dir', $pluginDir) }

# --- lean tool set ----------------------------------------------------------------------
# Local models work better with few tools and a short system prompt: with the full set,
# the fast model kept calling extras (review findings, memory notes, skills) after it had
# solved the task and never ended its answer (docs\agent.md).
#   tools  built-in tools the model may use (Claude Code flag --tools); without Git Bash
#          the Bash tool is swapped for the PowerShell tool (lib\Machine.ps1)
#   env    switches of Claude Code, set for this process only
if ($agent.tools) {
    $tools = Get-AgentTools ([string]$agent.tools)
    $extraArgs += @('--tools', $tools)
    if ($tools -match '(^|,)PowerShell(,|$)') { $env:CLAUDE_CODE_USE_POWERSHELL_TOOL = '1' }
}
if ($agent.env) {
    foreach ($p in $agent.env.PSObject.Properties) { Set-Item -Path "Env:$($p.Name)" -Value ([string]$p.Value) }
}

# No telemetry, update checks or error reports to the cloud in local mode.
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

# Model, context and address; styled in a terminal, plain text when the output is redirected.
Get-LocalLookBanner $Model $server.baseUrl ([int]$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS) $ctx $pickerModels

# Git is the way back from anything the model changes. Only said to a person at a terminal.
if ($agent.gitCheck -and -not [Console]::IsOutputRedirected) {
    $note = Get-GitSafetyNote (Get-Location).Path
    if ($note) { "claude-local: $note" }
}

# --- run, then free the GPU memory ----------------------------------------------------
# The models this launcher can have loaded: the start model and the ones in the picker.
# finally also runs when the session is interrupted; a closed terminal window skips it,
# for that case the profiles set sleep-idle-seconds (docs\backend.md).
if (-not $OnExit) { $OnExit = [string]$agent.onExit }
if (-not $OnExit) { $OnExit = 'keep' }
$sessionModels = @($Model) + $pickerModels | Select-Object -Unique
$exitCode = 1
Register-AgentSession $Model
Enter-LocalLook                # tints the terminal warm while the local model works
$sessionStart = Get-Date
try {
    & $claude --model $Model @extraArgs @ClaudeArgs
    $exitCode = $LASTEXITCODE
} finally {
    Exit-LocalLook
    Get-LocalLookFarewell $sessionStart    # colourful styles say goodbye (lib\Style.ps1)
    "claude-local: $(Complete-AgentSession $OnExit $sessionModels)"
}
exit $exitCode
