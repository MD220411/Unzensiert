# Small measurements against a loaded model: speed, tool calling, image input, GPU memory.
# Used by Test-Model.ps1 and Benchmark-Models.ps1. Needs lib\Server.ps1. ASCII-only.

function Measure-Generation([string]$Model, [int]$MaxTokens = 400) {
    # Lets the model write code and returns the timing figures llama-server reports:
    #   genTps          answer speed in tokens/s
    #   tokens          generated tokens
    #   draftAcceptance share of speculative (MTP) tokens that were accepted, $null without MTP
    #   hasCode         the answer contains a Python function or class
    $r = Invoke-ServerApi '/v1/chat/completions' @{
        model      = $Model
        max_tokens = $MaxTokens
        messages   = @(@{ role = 'user'; content = 'Write a Python class that implements an LRU cache with get and put, plus a short usage example.' })
    }
    $acceptance = $null
    if ($r.timings.draft_n -gt 0) { $acceptance = [math]::Round($r.timings.draft_n_accepted / $r.timings.draft_n, 2) }
    $text = [string]$r.choices[0].message.content + [string]$r.choices[0].message.reasoning_content
    return [ordered]@{
        genTps          = [math]::Round($r.timings.predicted_per_second, 1)
        tokens          = [int]$r.timings.predicted_n
        draftAcceptance = $acceptance
        hasCode         = [bool]($text -match '(def |class )')
    }
}

function Measure-PromptSpeed([string]$Model) {
    # Sends a long prompt (about 20k tokens) and returns how fast the model reads it.
    # The prompt starts with a new id each time, so the prompt cache cannot help.
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("Run id $([guid]::NewGuid()). Below is a Python file.")
    for ($i = 0; $i -lt 450; $i++) {
        $null = $sb.AppendLine("def handler_$i(request, context):")
        $null = $sb.AppendLine("    value = context.lookup('key_$i', default=$i) + request.offset")
        $null = $sb.AppendLine("    return {'status': 200, 'value': value, 'handler': 'handler_$i'}")
    }
    $null = $sb.AppendLine('How many functions does the file define? Answer with the number only.')
    $r = Invoke-ServerApi '/v1/chat/completions' @{
        model      = $Model
        max_tokens = 16
        messages   = @(@{ role = 'user'; content = $sb.ToString() })
    }
    return [ordered]@{
        promptTokens = [int]$r.timings.prompt_n
        promptTps    = [math]::Round($r.timings.prompt_per_second, 1)
    }
}

function Test-ToolCall([string]$Model) {
    # Checks that the model answers a simple request with a well-formed tool call.
    # Returns ok ($true/$false) and a short detail text.
    $tools = @(@{
            type     = 'function'
            function = @{
                name        = 'read_file'
                description = 'Read a file from disk and return its content.'
                parameters  = @{
                    type       = 'object'
                    properties = @{ path = @{ type = 'string'; description = 'Path of the file' } }
                    required   = @('path')
                }
            }
        })
    try {
        $r = Invoke-ServerApi '/v1/chat/completions' @{
            model      = $Model
            max_tokens = 1024
            tools      = $tools
            messages   = @(@{ role = 'user'; content = 'What is inside the file src/main.py? Use the tool.' })
        }
        $call = $null
        if ($r.choices[0].message.tool_calls) { $call = $r.choices[0].message.tool_calls[0].function }
        if ($call -and $call.name -eq 'read_file' -and $call.arguments -match 'main\.py') {
            return [ordered]@{ ok = $true; detail = "$($call.name) $($call.arguments)" }
        }
        return [ordered]@{ ok = $false; detail = "no tool call, answer: $($r.choices[0].message.content)" }
    } catch {
        return [ordered]@{ ok = $false; detail = $_.Exception.Message }
    }
}

function New-TestImageBase64([string]$Text) {
    # A small PNG with $Text drawn on it, as base64.
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 448, 224
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $font = New-Object System.Drawing.Font 'Arial', 72
    $stream = New-Object System.IO.MemoryStream
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.DrawString($Text, $font, [System.Drawing.Brushes]::Black, 40, 50)
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return [Convert]::ToBase64String($stream.ToArray())
    } finally {
        $stream.Dispose(); $font.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
    }
}

function Test-ImageInput([string]$Model) {
    # Checks that the model can read an image the way Claude Code hands it over: as the
    # result of a Read tool call on the Anthropic endpoint (/v1/messages), followed by a
    # text block in the same message. Claude Code adds reminders there; llama-server puts
    # that text in front of the tool result, which a chat template without the "agent fix"
    # rejects or renders in the wrong order (docs\modelle.md).
    # Returns ok ($true/$false) and a short detail text.
    $number = [string](Get-Random -Minimum 1000 -Maximum 9999)
    $tools = @(@{
            name         = 'Read'
            description  = 'Read a file from disk. Image files are returned as images.'
            input_schema = @{
                type       = 'object'
                properties = @{ file_path = @{ type = 'string' } }
                required   = @('file_path')
            }
        })
    $messages = @(
        @{ role = 'user'; content = 'Which number is shown in the image number.png? Answer with the number only.' },
        @{ role = 'assistant'; content = @(@{ type = 'tool_use'; id = 'toolu_01'; name = 'Read'; input = @{ file_path = 'number.png' } }) },
        @{ role = 'user'; content = @(
                @{
                    type        = 'tool_result'
                    tool_use_id = 'toolu_01'
                    content     = @(@{ type = 'image'; source = @{ type = 'base64'; media_type = 'image/png'; data = (New-TestImageBase64 $number) } })
                },
                @{ type = 'text'; text = '<system-reminder>Answer in the language of the user.</system-reminder>' }
            )
        }
    )
    try {
        $r = Invoke-ServerApi '/v1/messages' @{ model = $Model; max_tokens = 2048; tools = $tools; messages = $messages }
        $answer = (@($r.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ' ').Trim()
        if ($answer -match $number) { return [ordered]@{ ok = $true; detail = "read the number $number from a test image" } }
        return [ordered]@{ ok = $false; detail = "image shows $number, answer: $answer" }
    } catch {
        return [ordered]@{ ok = $false; detail = $_.Exception.Message }
    }
}

function Get-ClaudeCodeVersion {
    # Version of the installed Claude Code, e.g. "2.1.325", or "unknown". Claude Code
    # updates itself and changes prompt and tools with it, so results name the version.
    try {
        $text = [string](& claude --version 2>$null | Select-Object -First 1)
        if ($text -match '(\d+(\.\d+)+)') { return $Matches[1] }
    } catch {}
    return 'unknown'
}

function Get-GpuMemory {
    # Used memory per GPU in MiB as reported by nvidia-smi, e.g. "RTX 5070 Ti 13300, RTX 3060 7631".
    $rows = @(& nvidia-smi --query-gpu=name,memory.used --format=csv,noheader,nounits)
    return (($rows | ForEach-Object {
                $parts = $_.Split(',')
                "$($parts[0].Replace('NVIDIA GeForce ', '').Trim()) $($parts[1].Trim())"
            }) -join ', ')
}
