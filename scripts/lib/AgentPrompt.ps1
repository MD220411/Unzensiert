# The system prompt of the agent Unzensiert: config\unzensiert-prompt.md with the facts of
# this session filled in, then the instructions of the project (AGENTS.md or CLAUDE.md in
# the project folder and the folders above it) and the working rules ("rulesFile" in
# config\agent.json). Needs lib\Config.ps1. Keep this file ASCII-only.

function Get-ProjectInstructions([string]$Cwd, $Names) {
    # Instruction files from the outermost folder down to the project folder; per folder
    # the first of $Names that exists (many projects keep AGENTS.md and CLAUDE.md equal).
    $found = New-Object System.Collections.ArrayList
    $dir = $Cwd
    while ($dir) {
        foreach ($name in $Names) {
            $file = Join-Path $dir $name
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                $found.Insert(0, @{ path = $file; text = [System.IO.File]::ReadAllText($file) })
                break
            }
        }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return @($found)
}

function Get-GitFact([string]$Cwd) {
    # One line about git for the prompt.
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return 'Git is not installed.' }
        $inside = & cmd /c "git -C `"$Cwd`" rev-parse --is-inside-work-tree 2>nul"
        if ("$inside".Trim() -ne 'true') { return 'The project folder is not a git repository, so changes cannot be undone with git.' }
        $branch = ("$(& cmd /c "git -C `"$Cwd`" rev-parse --abbrev-ref HEAD 2>nul")").Trim()
        $changes = @(& cmd /c "git -C `"$Cwd`" status --porcelain 2>nul").Count
        return "Git repository, branch $branch, $changes uncommitted change(s)."
    } finally {
        $ErrorActionPreference = $saved
    }
}

function New-AgentSystemPrompt($Session) {
    $cfg = Get-AgentSettings
    $agent = Get-AgentConfig
    $text = [System.IO.File]::ReadAllText((Join-Path $script:ConfigDir ([string]$cfg.promptFile)))
    $shells = 'Windows PowerShell 5.1 (tool PowerShell); Git Bash is not installed, there is no Bash tool'
    if ($Session.gitBash) { $shells = 'Git Bash (tool Bash) and Windows PowerShell 5.1 (tool PowerShell)' }
    $facts = @{
        '{{date}}' = (Get-Date).ToString('yyyy-MM-dd')
        '{{os}}' = [string][Environment]::OSVersion.Version
        '{{cwd}}' = $Session.cwd
        '{{git}}' = (Get-GitFact $Session.cwd)
        '{{shells}}' = $shells
        '{{timeout}}' = [string]$cfg.commandTimeoutSeconds
    }
    foreach ($k in $facts.Keys) { $text = $text.Replace($k, $facts[$k]) }
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append($text.TrimEnd())
    # git older than 2.54 cannot take the co-author hook (lib\AgentTools.ps1), so the model
    # writes the line itself
    $coAuthor = Get-CoAuthorSetup
    if ($coAuthor.trailer -and -not $coAuthor.hook) {
        $null = $sb.Append("`n`n# Commits`nWhen you create a git commit, end its message with an empty line and then exactly this line:`n$($coAuthor.trailer)")
    }
    $project = @(Get-ProjectInstructions $Session.cwd @($cfg.projectFiles))
    if ($project.Count -gt 0) {
        $null = $sb.Append("`n`n# Instructions of this project`nFollow them; they come from the user.")
        foreach ($p in $project) { $null = $sb.Append("`n`n## From $($p.path)`n`n$($p.text.Trim())") }
    }
    if ($agent.rulesFile) {
        $rules = Join-Path $script:ConfigDir ([string]$agent.rulesFile)
        if (Test-Path $rules) { $null = $sb.Append("`n`n# Working rules`n`n" + [System.IO.File]::ReadAllText($rules).Trim()) }
    }
    $Session.instructionFiles = @($project | ForEach-Object { $_.path })
    return $sb.ToString()
}
