# The agent Unzensiert talks to llama-server: JSON in and out, and one streamed chat request
# (OpenAI-compatible /v1/chat/completions) with tools. Used by lib\AgentLoop.ps1.
# Needs lib\Config.ps1 and lib\Server.ps1. Keep this file ASCII-only.
#
# JSON goes through the JavaScriptSerializer of .NET: ConvertTo-Json of Windows PowerShell
# 5.1 takes seconds for a long conversation and cuts deep objects. Messages are therefore
# kept as hashtables and arrays, never as PowerShell objects. Values that come out of
# cmdlets (New-Object, Join-Path, Get-Date) are wrapped in a PSObject, which the serializer
# cannot handle: in data for the server use [type]::new(), [string] and [datetime]::Now.
# ConvertTo-AgentJson unwraps such values as a fallback, at the cost of a copy.

Add-Type -AssemblyName System.Web.Extensions
$script:AgentJson = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$script:AgentJson.MaxJsonLength = [int]::MaxValue
$script:AgentJson.RecursionLimit = 200

function ConvertTo-PlainData($Value) {
    # A copy of $Value without PSObject wrappers: dictionaries, lists, strings and numbers.
    if ($null -eq $Value) { return $null }
    if ($Value -is [psobject]) { $Value = $Value.psobject.BaseObject }
    if ($Value -is [string] -or $Value -is [System.ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $d = [System.Collections.Generic.Dictionary[string, object]]::new()
        foreach ($k in @($Value.Keys)) { $d[[string]$k] = ConvertTo-PlainData $Value[$k] }
        return $d
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { $list.Add((ConvertTo-PlainData $item)) }
        return , $list
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $d = [System.Collections.Generic.Dictionary[string, object]]::new()
        foreach ($p in $Value.PSObject.Properties) { $d[$p.Name] = ConvertTo-PlainData $p.Value }
        return $d
    }
    return [string]$Value
}

function ConvertTo-AgentJson($Value) {
    try { return $script:AgentJson.Serialize($Value) }
    catch { return $script:AgentJson.Serialize((ConvertTo-PlainData $Value)) }
}

# Functions here return lists with a leading comma (return , $list): PowerShell would unroll
# a list on its way out of a function, and a list with one element would arrive as that
# element.

function ConvertFrom-AgentJson([string]$Text) {
    # Objects become dictionaries, lists object arrays.
    return , $script:AgentJson.DeserializeObject($Text)
}

function Get-DictValue($Dict, [string]$Key) {
    # A value of a parsed JSON object or a hashtable, $null if the key is missing.
    # (the IDictionary cast: Dictionary<string,object> of the JSON reader has no Contains of its own)
    if ($null -ne $Dict -and $Dict -is [System.Collections.IDictionary] -and ([System.Collections.IDictionary]$Dict).Contains($Key)) { return , $Dict[$Key] }
    return $null
}

function Read-ApiError($Exception) {
    # The message llama-server sends with an error status.
    try {
        $reader = New-Object System.IO.StreamReader($Exception.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        $parsed = ConvertFrom-AgentJson $text
        $err = Get-DictValue $parsed 'error'
        if ($err) { return [string](Get-DictValue $err 'message') }
        return $text
    } catch {
        return $Exception.Message
    }
}

function New-ChatStreamState {
    return @{
        content = New-Object System.Text.StringBuilder; reasoning = New-Object System.Text.StringBuilder
        calls = New-Object System.Collections.ArrayList; finish = ''; cancelled = $false; done = $false
        promptTokens = 0; completionTokens = 0; cachedTokens = 0; tokensPerSecond = 0.0; promptMs = 0.0
    }
}

function Update-ChatStreamState($State, [string]$Line, [scriptblock]$OnEvent) {
    # Takes one line of the event stream ("data: {...}") into $State and tells OnEvent
    # (& $OnEvent <reasoning|content|tool> <text>) what arrived.
    if (-not $Line.StartsWith('data: ')) { return }
    $data = $Line.Substring(6)
    if ($data -eq '[DONE]') { $State.done = $true; return }
    $chunk = ConvertFrom-AgentJson $data
    $usage = Get-DictValue $chunk 'usage'
    if ($usage) {
        $State.promptTokens = [int](Get-DictValue $usage 'prompt_tokens')
        $State.completionTokens = [int](Get-DictValue $usage 'completion_tokens')
        $details = Get-DictValue $usage 'prompt_tokens_details'
        if ($details) { $State.cachedTokens = [int](Get-DictValue $details 'cached_tokens') }
    }
    $timings = Get-DictValue $chunk 'timings'
    if ($timings) {
        $State.tokensPerSecond = [double](Get-DictValue $timings 'predicted_per_second')
        $State.promptMs = [double](Get-DictValue $timings 'prompt_ms')
    }
    $choices = Get-DictValue $chunk 'choices'
    if (-not $choices -or $choices.Count -eq 0) { return }
    $choice = $choices[0]
    $finish = Get-DictValue $choice 'finish_reason'
    if ($finish) { $State.finish = [string]$finish }
    $delta = Get-DictValue $choice 'delta'
    if (-not $delta) { return }
    $text = Get-DictValue $delta 'reasoning_content'
    if ($text) {
        $null = $State.reasoning.Append([string]$text)
        if ($OnEvent) { $null = & $OnEvent 'reasoning' ([string]$text) }
    }
    $text = Get-DictValue $delta 'content'
    if ($text) {
        $null = $State.content.Append([string]$text)
        if ($OnEvent) { $null = & $OnEvent 'content' ([string]$text) }
    }
    $toolDeltas = Get-DictValue $delta 'tool_calls'
    if ($toolDeltas) {
        foreach ($td in $toolDeltas) {
            $index = [int](Get-DictValue $td 'index')
            while ($State.calls.Count -le $index) { $null = $State.calls.Add(@{ id = ''; name = ''; arguments = (New-Object System.Text.StringBuilder) }) }
            $call = $State.calls[$index]
            $id = Get-DictValue $td 'id'
            if ($id) { $call.id = [string]$id }
            $fn = Get-DictValue $td 'function'
            if ($fn) {
                $name = Get-DictValue $fn 'name'
                if ($name) {
                    $call.name = [string]$name
                    if ($OnEvent) { $null = & $OnEvent 'tool' ([string]$name) }
                }
                $argText = Get-DictValue $fn 'arguments'
                if ($argText) { $null = $call.arguments.Append([string]$argText) }
            }
        }
    }
}

function Complete-ChatStreamState($State) {
    # The finished answer: @{ content; reasoning; toolCalls = @(@{ id; name; arguments });
    # finish; cancelled; promptTokens; completionTokens; cachedTokens; tokensPerSecond; promptMs }
    $calls = @()
    foreach ($c in $State.calls) {
        if (-not $c.name) { continue }
        $id = $c.id
        if (-not $id) { $id = 'call_' + [guid]::NewGuid().ToString('N').Substring(0, 12) }
        $calls += , @{ id = $id; name = $c.name; arguments = $c.arguments.ToString() }
    }
    return @{
        content = $State.content.ToString(); reasoning = $State.reasoning.ToString(); toolCalls = $calls
        finish = $State.finish; cancelled = $State.cancelled
        promptTokens = $State.promptTokens; completionTokens = $State.completionTokens; cachedTokens = $State.cachedTokens
        tokensPerSecond = $State.tokensPerSecond; promptMs = $State.promptMs
    }
}

function New-ChatRequestBody([string]$Model, $Messages, $Tools, [int]$MaxTokens, [bool]$ParallelToolCalls) {
    # The body of a chat request. parallel_tool_calls says that several tool calls in one
    # answer are welcome; llama-server b12433 takes them with the Qwen templates also without
    # it (measured on 2026-11-21), a build that keeps to the OpenAI default would allow one.
    $body = @{ model = $Model; messages = $Messages; stream = $true; stream_options = @{ include_usage = $true }; max_tokens = $MaxTokens }
    if ($Tools) {
        $body['tools'] = $Tools
        if ($ParallelToolCalls) { $body['parallel_tool_calls'] = $true }
    }
    return $body
}

function Invoke-ChatStream {
    # Sends one chat request and reads the answer as it streams in.
    #   OnEvent    script block, see Update-ChatStreamState
    #   ShouldStop script block; $true stops the request (Esc or Ctrl+C at the terminal)
    #   ParallelToolCalls  several tool calls in one answer are welcome ("parallelToolCalls"
    #              in config\unzensiert.json, New-ChatRequestBody)
    # Returns the result of Complete-ChatStreamState.
    param(
        [string]$Model,
        $Messages,
        $Tools,
        [int]$MaxTokens = 16384,
        [scriptblock]$OnEvent,
        [scriptblock]$ShouldStop,
        [bool]$ParallelToolCalls = $false
    )
    $body = New-ChatRequestBody $Model $Messages $Tools $MaxTokens $ParallelToolCalls
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-AgentJson $body))

    $request = [System.Net.HttpWebRequest]::Create("$((Get-ServerConfig).baseUrl)/v1/chat/completions")
    $request.Method = 'POST'
    $request.ContentType = 'application/json; charset=utf-8'
    $request.Timeout = 3600000
    $request.ReadWriteTimeout = 3600000
    # only to llama-server of the install folder (lib\Server.ps1)
    $key = Get-ServerRequestKey
    if ($key) { $request.Headers.Add('Authorization', "Bearer $key") }
    $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream()
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Close() }

    try {
        $response = $request.GetResponse()
    } catch {
        # .NET exceptions arrive wrapped (MethodInvocationException): look for the web error
        $ex = $_.Exception
        while ($ex -and -not ($ex -is [System.Net.WebException])) { $ex = $ex.InnerException }
        if ($ex -and $ex.Response) { throw "llama-server: $(Read-ApiError $ex)" }
        throw
    }
    $state = New-ChatStreamState
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
    try {
        while (-not $state.done) {
            # waiting for the next line can take long (reading a big prompt): keep asking
            # whether the user wants to stop
            $task = $reader.ReadLineAsync()
            while (-not $task.Wait(100)) {
                if ($ShouldStop -and (& $ShouldStop)) { $state.cancelled = $true; break }
            }
            if ($state.cancelled) { $request.Abort(); break }
            $line = $task.Result
            if ($null -eq $line) { break }
            $null = Update-ChatStreamState $state $line $OnEvent
            if ($ShouldStop -and (& $ShouldStop)) { $state.cancelled = $true; $request.Abort(); break }
        }
    } catch {
        if (-not $state.cancelled) { throw }
    } finally {
        try { $reader.Close() } catch {}
        try { $response.Close() } catch {}
    }
    return (Complete-ChatStreamState $state)
}
