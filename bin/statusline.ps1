# Windows PowerShell Statusline for Google Antigravity CLI (agy)
# Native, zero-dependency script utilizing built-in .NET classes and ANSI sequences.
$ErrorActionPreference = "Stop"

try {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

    # ─── Define Unicode Characters via Hex Codes (PowerShell 5.1 Safe) ───────────
    $charCircleFull = [char]0x25cf
    $charCircleEmpty = [char]0x25cb
    $charDiamond = [char]0x25c6
    $charGear = [char]0x2699
    $charWrench = [char]::ConvertFromUtf32(0x1F527)
    $charHourglass = [char]0x231b
    $charBlockFull = [char]0x2588
    $charBlockDark = [char]0x2593
    $charBlockMed = [char]0x2592
    $charBlockLight = [char]0x2591
    $charDot = [char]0x00b7
    $charSlash = [char]0x002f
    $charPipe = [char]0x2502
    $charCornerTop = [char]0x256d
    $charLine = [char]0x2500
    $charCornerBot = [char]0x2570
    $charJoin = [char]0x251c
    $charReset = [char]0x27f3
    $charSigma = [char]0x03A3
    $charEllipsis = [char]0x2026

    # ─── Configuration Constants ──────────────────────────────────────────────────
    $CONFIG_LAYOUT_WIDE_COLS = 120
    $CONFIG_LAYOUT_MED_COLS = 100
    $CONFIG_BAR_LEN_CTX = 15
    $CONFIG_BAR_LEN_CTX_NARROW = 8
    $CONFIG_BAR_LEN_QUOTA = 10
    $CONFIG_CTX_WARN_PCT = 60
    $CONFIG_CTX_CRIT_PCT = 90
    $CONFIG_QUOTA_INFO_PCT = 50
    $CONFIG_QUOTA_WARN_PCT = 70
    $CONFIG_QUOTA_CRIT_PCT = 90

    # ─── Helper Functions ─────────────────────────────────────────────────────────
    function Get-SafeDouble {
        param($val, [double]$default = 0.0)
        if ($null -eq $val) { return $default }
        $out = 0.0
        if ([double]::TryParse($val.ToString(), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$out)) {
            return $out
        }
        return $default
    }

    function Format-Tok {
        param([double]$n)
        if ($n -ge 1000000) {
            return ($n / 1000000.0).ToString("F2", [System.Globalization.CultureInfo]::InvariantCulture) + "M"
        }
        if ($n -ge 1000) {
            return ($n / 1000.0).ToString("F1", [System.Globalization.CultureInfo]::InvariantCulture) + "k"
        }
        return ([Math]::Round($n)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    function Get-DisplayWidth {
        param([string]$elem)
        if ([string]::IsNullOrEmpty($elem)) { return 0 }
        $cp = [char]::ConvertToUtf32($elem, 0)
        if (($cp -ge 0xFE00 -and $cp -le 0xFE0F) -or $cp -eq 0x200D) { return 0 }
        if ($cp -lt 0x20) { return 0 }
        if (($cp -ge 0x1F300 -and $cp -le 0x1FAFF) -or $cp -eq 0x231A -or $cp -eq 0x231B) { return 2 }
        if (($cp -ge 0x2E80 -and $cp -le 0x9FFF) -or ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or ($cp -ge 0xFE30 -and $cp -le 0xFE6F) -or ($cp -ge 0xFF00 -and $cp -le 0xFFEF)) {
            return 2
        }
        return 1
    }

    function Format-TruncatedAnsiLine {
        param(
            [string]$text,
            [int]$maxCols,
            [string]$resetSeq
        )
        if ([string]::IsNullOrEmpty($text) -or $maxCols -lt 1) { return $text }
        $ansiRegex = [regex]'\x1b\[[0-9;]*[A-Za-z]'
        $pos = 0
        $vis = 0
        $out = [System.Text.StringBuilder]::new()
        $lastFitLen = 0
        $truncated = $false

        while ($pos -lt $text.Length) {
            $m = $ansiRegex.Match($text, $pos)
            $segEnd = if ($m.Success -and $m.Index -eq $pos) { $pos } elseif ($m.Success) { $m.Index } else { $text.Length }

            if ($m.Success -and $m.Index -eq $pos) {
                [void]$out.Append($m.Value)
                if ($vis -le ($maxCols - 1)) {
                    $lastFitLen = $out.Length
                }
                $pos += $m.Length
                continue
            }

            $plainSeg = $text.Substring($pos, $segEnd - $pos)
            $enum = [System.Globalization.StringInfo]::GetTextElementEnumerator($plainSeg)
            while ($enum.MoveNext()) {
                $elem = $enum.GetTextElement()
                $cw = Get-DisplayWidth -elem $elem
                if (($vis + $cw) -gt $maxCols) {
                    $truncated = $true
                    break
                }
                [void]$out.Append($elem)
                $vis += $cw
                if ($vis -le ($maxCols - 1)) {
                    $lastFitLen = $out.Length
                }
            }
            if ($truncated) { break }
            $pos = $segEnd
        }

        if ($truncated) {
            if ($maxCols -ge 1) {
                return $out.ToString(0, $lastFitLen) + $charEllipsis + $resetSeq
            }
            return $resetSeq
        }
        return $out.ToString()
    }

    function Get-TranscriptMetrics {
        param([string]$path)
        $emptyResult = @{
            HasTranscript = $false
            Turns = 0
            Compacts = 0
            Sigma = 0.0
            AvgTps = 0.0
        }
        if ([string]::IsNullOrEmpty($path) -or -not (Test-Path -LiteralPath $path)) {
            return $emptyResult
        }

        $fileInfo = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if ($null -eq $fileInfo -or $fileInfo.Length -le 0) {
            return $emptyResult
        }
        $fileSize = [long]$fileInfo.Length

        $sha = [System.Security.Cryptography.SHA256]::Create()
        $pathHashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($path))
        $pathHash = ([System.BitConverter]::ToString($pathHashBytes)).Replace("-", "").Substring(0, 16)
        $sha.Dispose()
        $cacheFile = Join-Path ([System.IO.Path]::GetTempPath()) "agy_sl_$pathHash.cache"

        $cOffset = [long]0
        $cTurns = 0
        $cPlanners = 0
        $cCompacts = 0
        $cSkipDrop = $false
        $cSigma = 0.0
        $cPrevCtx = 0.0
        $cPrevPlanner = $false
        $cPrevOut = 0.0
        $cPrevTs = [double]-1
        $speedSamples = [System.Collections.Generic.List[string]]::new()

        if (Test-Path -LiteralPath $cacheFile) {
            try {
                $cached = [System.IO.File]::ReadAllText($cacheFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                if ($null -ne $cached -and $cached.path -eq $path -and [long]$cached.offset -le $fileSize) {
                    $cOffset = [long]$cached.offset
                    $cTurns = [int]$cached.turns
                    $cPlanners = [int]$cached.planners
                    $cCompacts = [int]$cached.compacts
                    $cSkipDrop = [bool]$cached.skip_drop
                    $cSigma = [double]$cached.sigma
                    $cPrevCtx = [double]$cached.prev_ctx
                    $cPrevPlanner = [bool]$cached.prev_planner
                    $cPrevOut = [double]$cached.prev_out
                    $cPrevTs = [double]$cached.prev_ts
                    if ($null -ne $cached.samples) {
                        foreach ($sp in $cached.samples) {
                            $speedSamples.Add($sp.ToString())
                        }
                    }
                }
            } catch {}
        }

        if ($fileSize -gt $cOffset) {
            $fs = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                [void]$fs.Seek($cOffset, [System.IO.SeekOrigin]::Begin)
                $deltaLen = [int]($fileSize - $cOffset)
                $buf = New-Object byte[] $deltaLen
                $readTotal = 0
                while ($readTotal -lt $deltaLen) {
                    $r = $fs.Read($buf, $readTotal, $deltaLen - $readTotal)
                    if ($r -le 0) { break }
                    $readTotal += $r
                }

                # Only consume complete newline-terminated lines so half-written lines wait for next tick
                $lastNl = -1
                for ($bi = $readTotal - 1; $bi -ge 0; $bi--) {
                    if ($buf[$bi] -eq 10) {
                        $lastNl = $bi
                        break
                    }
                }

                if ($lastNl -ge 0) {
                    $chunk = [System.Text.Encoding]::UTF8.GetString($buf, 0, $lastNl + 1)
                    foreach ($line in ($chunk -split "`n")) {
                        $trimmed = $line.Trim()
                        if ([string]::IsNullOrEmpty($trimmed)) { continue }
                        $obj = $null
                        try { $obj = ConvertFrom-Json $trimmed } catch { continue }
                        if ($null -eq $obj) { continue }

                        $stepType = if ($obj.type) { $obj.type.ToString() } else { "" }
                        if ([string]::IsNullOrEmpty($stepType)) { continue }

                        $stepEpoch = [double]-1
                        if ($obj.created_at) {
                            $dto = [DateTimeOffset]::MinValue
                            if ([DateTimeOffset]::TryParse($obj.created_at.ToString(), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$dto)) {
                                $stepEpoch = [double]$dto.ToUnixTimeSeconds()
                            }
                        }

                        if ($cPrevPlanner -and $stepType -eq "GENERIC" -and $stepEpoch -ge 0 -and $cPrevTs -ge 0) {
                            $dt = $stepEpoch - $cPrevTs
                            if ($dt -ge 1.0 -and $dt -le 120.0 -and $cPrevOut -gt 0) {
                                $speedSamples.Add("$cPrevOut`:$dt")
                            }
                        }
                        $cPrevPlanner = $false

                        if ($stepType -eq "USER_INPUT") {
                            $cTurns++
                        } elseif ($stepType -eq "CHECKPOINT" -or $stepType -eq "COMPACT") {
                            $cCompacts++
                            $cSkipDrop = $true
                        } elseif ($stepType -eq "PLANNER_RESPONSE") {
                            $cPlanners++
                            $sIn = Get-SafeDouble $obj.input_tokens 0.0
                            $sCr = Get-SafeDouble $obj.cache_read_tokens 0.0
                            $sCc = Get-SafeDouble $obj.cache_creation_tokens 0.0
                            $sOut = Get-SafeDouble $obj.output_tokens 0.0
                            $cSigma += ($sIn + $sCr + $sCc + $sOut)
                            $curCtx = $sIn + $sCr
                            if (-not $cSkipDrop -and $cPrevCtx -gt 0 -and ($cPrevCtx - $curCtx) -gt 30000) {
                                $cCompacts++
                            }
                            $cSkipDrop = $false
                            $cPrevCtx = $curCtx
                            $cPrevPlanner = $true
                            $cPrevOut = $sOut
                            $cPrevTs = $stepEpoch
                        }
                    }

                    if ($speedSamples.Count -gt 10) {
                        $speedSamples = [System.Collections.Generic.List[string]]::new($speedSamples.GetRange($speedSamples.Count - 10, 10))
                    }
                    $cOffset += ($lastNl + 1)

                    try {
                        $cacheObj = [PSCustomObject]@{
                            path = $path
                            offset = $cOffset
                            turns = $cTurns
                            planners = $cPlanners
                            compacts = $cCompacts
                            skip_drop = $cSkipDrop
                            sigma = $cSigma
                            prev_ctx = $cPrevCtx
                            prev_planner = $cPrevPlanner
                            prev_out = $cPrevOut
                            prev_ts = $cPrevTs
                            samples = @($speedSamples)
                        }
                        [System.IO.File]::WriteAllText($cacheFile, ($cacheObj | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
                    } catch {}
                }
            } finally {
                $fs.Dispose()
            }
        }

        $displayTurns = if ($cTurns -eq 0 -and $cPlanners -gt 0) { 1 } else { $cTurns }
        $avgTps = 0.0
        if ($speedSamples.Count -gt 0) {
            $sumOut = 0.0
            $sumSec = 0.0
            foreach ($sp in $speedSamples) {
                $kv = $sp.Split(":")
                if ($kv.Length -eq 2) {
                    $sumOut += Get-SafeDouble $kv[0] 0.0
                    $sumSec += Get-SafeDouble $kv[1] 0.0
                }
            }
            if ($sumSec -gt 0) { $avgTps = $sumOut / $sumSec }
        }

        return @{
            HasTranscript = $true
            Turns = $displayTurns
            Compacts = $cCompacts
            Sigma = $cSigma
            AvgTps = $avgTps
        }
    }

    # ─── Read Stdin ─────────────────────────────────────────────────────────────
    $jsonText = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        Write-Output "agy"
        exit 0
    }

    try {
        $data = ConvertFrom-Json $jsonText
    } catch {
        Write-Output "agy (JSON parse error)"
        exit 0
    }

    # ─── Configuration Loader (Optional ~/.gemini/statusline.json) ───────────────
    $configPath = Join-Path ([System.Environment]::GetFolderPath("UserProfile")) ".gemini\statusline.json"
    $config = @{
        show_quota = $true
        show_additional_stats = $true
        hide_zero_stats = $true
        show_state_indicator = $true
    }

    if (Test-Path $configPath) {
        try {
            $loaded = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($null -ne $loaded) {
                foreach ($key in $config.Keys.Clone()) {
                    if ($null -ne $loaded.$key) {
                        $config[$key] = [bool]$loaded.$key
                    }
                }
            }
        } catch {}
    }

    # ─── ANSI Colors & Formatting ───────────────────────────────────────────────
    $esc = [char]27
    $R = "$esc[0m"
    $B = "$esc[1m"
    $I = "$esc[3m"
    $FG_WHITE = "$esc[37m"
    $FG_GRAY = "$esc[90m"
    $FG_BRIGHT_RED = "$esc[91m"
    $FG_BRIGHT_GREEN = "$esc[92m"
    $FG_BRIGHT_YELLOW = "$esc[93m"
    $FG_BRIGHT_BLUE = "$esc[94m"
    $FG_BRIGHT_MAGENTA = "$esc[95m"
    $FG_BRIGHT_CYAN = "$esc[96m"
    $FG_BRIGHT_WHITE = "$esc[97m"

    $NUM_COLOR = "$FG_BRIGHT_WHITE$B"

    # ─── Extract Data Fields ─────────────────────────────────────────────────────
    $state = if ($data.agent_state) { $data.agent_state.ToString() } else { "idle" }
    $usedPct = if ($data.context_window -and $null -ne $data.context_window.used_percentage) { Get-SafeDouble $data.context_window.used_percentage 0.0 } else { 0.0 }
    $ctxMaxTok = if ($data.context_window -and $null -ne $data.context_window.context_window_size) { Get-SafeDouble $data.context_window.context_window_size 0.0 } else { 0.0 }
    $totalInTok = if ($data.context_window -and $null -ne $data.context_window.total_input_tokens) { Get-SafeDouble $data.context_window.total_input_tokens 0.0 } else { 0.0 }
    $curInTok = 0.0
    $curCacheCreate = 0.0
    $curCacheRead = 0.0
    if ($data.context_window -and $null -ne $data.context_window.current_usage) {
        $cu = $data.context_window.current_usage
        $curInTok = Get-SafeDouble $cu.input_tokens 0.0
        $curCacheCreate = Get-SafeDouble $cu.cache_creation_input_tokens 0.0
        $curCacheRead = Get-SafeDouble $cu.cache_read_input_tokens 0.0
    }
    $cacheDenom = $curInTok + $curCacheCreate + $curCacheRead
    $cachePct = if ($cacheDenom -gt 0) { ($curCacheRead * 100.0) / $cacheDenom } else { 0.0 }

    if ($ctxMaxTok -gt 0 -and $usedPct -gt 0) {
        $ctxUsedTok = $ctxMaxTok * $usedPct / 100.0
    } elseif ($cacheDenom -gt 0) {
        $ctxUsedTok = $cacheDenom
    } else {
        $ctxUsedTok = $totalInTok
    }

    $transcriptPath = if ($data.transcript_path) { $data.transcript_path.ToString().Trim() } else { "" }
    if ($transcriptPath.StartsWith("file://")) {
        try { $transcriptPath = ([Uri]$transcriptPath).LocalPath } catch { $transcriptPath = $transcriptPath -replace '^file://', '' }
    }
    if ($transcriptPath -eq "~" -or $transcriptPath.StartsWith("~/") -or $transcriptPath.StartsWith("~\")) {
        $homeDir = [System.Environment]::GetFolderPath("UserProfile")
        $transcriptPath = if ($transcriptPath -eq "~") { $homeDir } else { Join-Path $homeDir $transcriptPath.Substring(2) }
    }
    if (-not [string]::IsNullOrEmpty($transcriptPath) -and -not (Test-Path -LiteralPath $transcriptPath)) {
        $altTranscriptPath = $transcriptPath -replace '\\antigravity\\', '\antigravity-cli\'
        if (Test-Path -LiteralPath $altTranscriptPath) {
            $transcriptPath = $altTranscriptPath
        }
    }

    $tMetrics = Get-TranscriptMetrics -path $transcriptPath
    $hasTranscript = [bool]$tMetrics.HasTranscript
    $turnsCount = [int]$tMetrics.Turns
    $compactCount = [int]$tMetrics.Compacts
    $sigmaTokens = [double]$tMetrics.Sigma
    $avgTokPerSec = [double]$tMetrics.AvgTps

    $vcsBranch = if ($data.vcs -and $data.vcs.branch) { $data.vcs.branch.ToString() } else { "" }
    $vcsDirty = if ($data.vcs -and $null -ne $data.vcs.dirty) { [bool]$data.vcs.dirty } else { $false }
    $sandboxEnabled = if ($data.sandbox -and $null -ne $data.sandbox.enabled) { [bool]$data.sandbox.enabled } else { $false }
    $artifactCount = if ($null -ne $data.artifact_count) { Get-SafeDouble $data.artifact_count 0 } else { 0 }
    $subagentCount = if ($data.subagents -and $data.subagents -is [System.Array]) { $data.subagents.Length } elseif ($data.subagents) { 1 } else { 0 }
    $taskCount = if ($null -ne $data.task_count) { Get-SafeDouble $data.task_count 0 } else { 0 }
    $modelDisplayName = if ($data.model -and $data.model.display_name) { $data.model.display_name.ToString() } else { "" }
    $modelId = if ($data.model -and $data.model.id) { $data.model.id.ToString().ToLower() } else { "" }
    $planTier = if ($data.plan_tier) { $data.plan_tier.ToString() } else { "" }
    $cols = if ($null -ne $data.terminal_width) { [int](Get-SafeDouble $data.terminal_width 80) } else { 80 }
    if ($cols -lt 20) { $cols = 80 }

    $Q_GEMINI_5H_REM = if ($data.quota -and $data.quota.'gemini-5h' -and $null -ne $data.quota.'gemini-5h'.remaining_fraction) { $data.quota.'gemini-5h'.remaining_fraction } else { $null }
    $Q_GEMINI_5H_RES = if ($data.quota -and $data.quota.'gemini-5h' -and $null -ne $data.quota.'gemini-5h'.reset_time) { $data.quota.'gemini-5h'.reset_time } else { $null }

    $Q_GEMINI_WK_REM = if ($data.quota -and $data.quota.'gemini-weekly' -and $null -ne $data.quota.'gemini-weekly'.remaining_fraction) { $data.quota.'gemini-weekly'.remaining_fraction } else { $null }
    $Q_GEMINI_WK_RES = if ($data.quota -and $data.quota.'gemini-weekly' -and $null -ne $data.quota.'gemini-weekly'.reset_time) { $data.quota.'gemini-weekly'.reset_time } else { $null }

    $Q_3P_5H_REM = if ($data.quota -and $data.quota.'3p-5h' -and $null -ne $data.quota.'3p-5h'.remaining_fraction) { $data.quota.'3p-5h'.remaining_fraction } else { $null }
    $Q_3P_5H_RES = if ($data.quota -and $data.quota.'3p-5h' -and $null -ne $data.quota.'3p-5h'.reset_time) { $data.quota.'3p-5h'.reset_time } else { $null }

    $Q_3P_WK_REM = if ($data.quota -and $data.quota.'3p-weekly' -and $null -ne $data.quota.'3p-weekly'.remaining_fraction) { $data.quota.'3p-weekly'.remaining_fraction } else { $null }
    $Q_3P_WK_RES = if ($data.quota -and $data.quota.'3p-weekly' -and $null -ne $data.quota.'3p-weekly'.reset_time) { $data.quota.'3p-weekly'.reset_time } else { $null }

    # Resolve CWD basename safely
    $cwd = if ($null -ne $data.cwd) { $data.cwd.ToString() } else { "" }
    if ([string]::IsNullOrEmpty($cwd) -or $cwd -eq "null") {
        try { $cwd = (Get-Location).Path } catch { $cwd = "" }
    }
    $dirName = $cwd
    try {
        if (-not [string]::IsNullOrEmpty($cwd)) {
            $trimmedCwd = $cwd.TrimEnd('\', '/')
            if (-not [string]::IsNullOrEmpty($trimmedCwd)) {
                $fn = [System.IO.Path]::GetFileName($trimmedCwd)
                if (-not [string]::IsNullOrEmpty($fn)) { $dirName = $fn }
            }
        }
    } catch {}

    # ─── Fallback Git Branch Detection ───────────────────────────────────────────
    if ([string]::IsNullOrEmpty($vcsBranch) -and -not [string]::IsNullOrEmpty($cwd) -and (Test-Path -LiteralPath $cwd)) {
        try {
            $gitOut = git -C $cwd status --porcelain --branch 2>$null
            if ($LASTEXITCODE -eq 0 -and $gitOut) {
                $gitLines = $gitOut -split "`n"
                if ($gitLines[0] -match '^## ([^.]+)') {
                    $vcsBranch = $Matches[1].Trim()
                    $vcsDirty = ($gitLines | Select-Object -Skip 1 | Where-Object { $_ -ne '' }).Count -gt 0
                }
            }
        } catch {}
    }

    # ─── LINE 1: State, Model, VCS Branch, Plan ──────────────────────────────────
    $agentStateBadge = ""
    if ($config.show_state_indicator) {
        switch ($state) {
            "idle" { $agentStateBadge = "$FG_BRIGHT_GREEN$B$charCircleFull READY$R" }
            "thinking" { $agentStateBadge = "$FG_BRIGHT_YELLOW$B$charDiamond THINKING$R" }
            "working" { $agentStateBadge = "$FG_BRIGHT_CYAN$B$charGear WORKING$R" }
            "tool_use" { $agentStateBadge = "$FG_BRIGHT_MAGENTA$B$charWrench TOOL$R" }
            default { $agentStateBadge = "$FG_WHITE$B$charHourglass $($state.ToUpper())$R" }
        }
    }

    $gitDirStatusBadge = "$FG_BRIGHT_CYAN$dirName$R"
    if (-not [string]::IsNullOrEmpty($vcsBranch)) {
        if ($vcsDirty) {
            $gitDirStatusBadge += " $FG_BRIGHT_GREEN($FG_BRIGHT_RED$vcsBranch$FG_BRIGHT_YELLOW*$FG_BRIGHT_GREEN)$R"
        } else {
            $gitDirStatusBadge += " $FG_BRIGHT_GREEN($FG_BRIGHT_BLUE$vcsBranch$FG_BRIGHT_GREEN)$R"
        }
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrEmpty($agentStateBadge)) {
        $parts.Add($agentStateBadge)
    }
    if (-not [string]::IsNullOrEmpty($modelDisplayName)) {
        $parts.Add("$FG_BRIGHT_MAGENTA$I$modelDisplayName$R")
    }
    if (-not [string]::IsNullOrEmpty($gitDirStatusBadge)) {
        $parts.Add($gitDirStatusBadge)
    }

    $LINE1 = [string]::Join("$FG_GRAY $charSlash $R", $parts)

    # ─── LINE 2: Context Bar & Stats ─────────────────────────────────────────────
    $barLen = if ($cols -lt $CONFIG_LAYOUT_WIDE_COLS) { $CONFIG_BAR_LEN_CTX_NARROW } else { $CONFIG_BAR_LEN_CTX }
    $filled = [int][Math]::Floor(($usedPct * $barLen) / 100)
    $remainder = ($usedPct * $barLen) % 100

    $barColor = $FG_BRIGHT_WHITE
    if ($usedPct -ge $CONFIG_CTX_CRIT_PCT) {
        $barColor = $FG_BRIGHT_RED
    } elseif ($usedPct -ge $CONFIG_CTX_WARN_PCT) {
        $barColor = $FG_BRIGHT_YELLOW
    }

    $bar = ""
    for ($idx = 0; $idx -lt $barLen; $idx++) {
        if ($idx -lt $filled) {
            $bar += $charBlockFull
        } elseif ($idx -eq $filled) {
            if ($remainder -ge 75) { $bar += $charBlockDark }
            elseif ($remainder -ge 50) { $bar += $charBlockMed }
            elseif ($remainder -ge 25) { $bar += $charBlockLight }
            else { $bar += $charDot }
        } else {
            $bar += $charDot
        }
    }

    $pctFmt = $usedPct.ToString("F1", [System.Globalization.CultureInfo]::InvariantCulture)
    if ($ctxMaxTok -gt 0) {
        $ctxUsedFmt = Format-Tok $ctxUsedTok
        $ctxMaxFmt = Format-Tok $ctxMaxTok
        $contextBarBadge = "${FG_GRAY}Ctx: $NUM_COLOR$ctxUsedFmt${FG_GRAY}/$NUM_COLOR$ctxMaxFmt ${FG_GRAY}($NUM_COLOR$pctFmt%${FG_GRAY}) $barColor[$bar]$R"
    } else {
        $contextBarBadge = "${FG_GRAY}Ctx: $barColor[$bar] $NUM_COLOR$pctFmt%$R"
    }

    $telemetryParts = [System.Collections.Generic.List[string]]::new()
    if ($hasTranscript) {
        $telemetryParts.Add("${FG_GRAY}Turns: $NUM_COLOR$turnsCount ${FG_GRAY}(Compact: $NUM_COLOR$compactCount${FG_GRAY})$R")
    }
    if ($cacheDenom -gt 0) {
        $cachePctFmt = $cachePct.ToString("F1", [System.Globalization.CultureInfo]::InvariantCulture)
        $cacheReadFmt = Format-Tok $curCacheRead
        $telemetryParts.Add("${FG_GRAY}Cache: $NUM_COLOR$cachePctFmt% ${FG_GRAY}($NUM_COLOR$cacheReadFmt${FG_GRAY})$R")
    }
    if ($hasTranscript -and $sigmaTokens -gt 0) {
        $sigmaFmt = Format-Tok $sigmaTokens
        $telemetryParts.Add("${FG_GRAY}${charSigma}Tok: $NUM_COLOR$sigmaFmt$R")
    }
    if ($hasTranscript -and $avgTokPerSec -gt 0) {
        $avgFmt = ([Math]::Round($avgTokPerSec)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $telemetryParts.Add("${FG_GRAY}Avg: $NUM_COLOR~$avgFmt tok/s$R")
    }

    $extraParts = [System.Collections.Generic.List[string]]::new()
    if ($config.show_additional_stats) {
        if (-not $config.hide_zero_stats -or $artifactCount -gt 0) {
            $extraParts.Add("${FG_GRAY}artifacts $NUM_COLOR$artifactCount$R")
        }
        if (-not $config.hide_zero_stats -or $subagentCount -gt 0) {
            $extraParts.Add("${FG_GRAY}subagents $NUM_COLOR$subagentCount$R")
        }
        if (-not $config.hide_zero_stats -or $taskCount -gt 0) {
            $extraParts.Add("${FG_GRAY}tasks $NUM_COLOR$taskCount$R")
        }
        if ($sandboxEnabled) {
            $extraParts.Add("${FG_GRAY}sandbox $FG_BRIGHT_GREEN${B}ON$R")
        } elseif (-not $config.hide_zero_stats) {
            $extraParts.Add("${FG_GRAY}sandbox off$R")
        }
    }

    $allTelemetry = [System.Collections.Generic.List[string]]::new()
    foreach ($tp in $telemetryParts) { $allTelemetry.Add($tp) }
    foreach ($ep in $extraParts) { $allTelemetry.Add($ep) }

    $dotSep = "$FG_GRAY $charDot $R"
    $pipeSep = "$FG_GRAY $charPipe $R"

    # ─── Quota Progress Bars ─────────────────────────────────────────────────────
    function Get-QuotaColor {
        param([int]$pct)
        if ($pct -ge $CONFIG_QUOTA_CRIT_PCT) { return $FG_BRIGHT_RED }
        if ($pct -ge $CONFIG_QUOTA_WARN_PCT) { return $FG_BRIGHT_YELLOW }
        if ($pct -ge $CONFIG_QUOTA_INFO_PCT) { return $FG_BRIGHT_CYAN }
        return $FG_BRIGHT_GREEN
    }

    function Get-QuotaBar {
        param(
            [double]$pct,
            [int]$width = $CONFIG_BAR_LEN_QUOTA
        )
        $clampedPct = [Math]::Max(0, [Math]::Min(100, $pct))
        $qFilled = [int][Math]::Round(($clampedPct * $width) / 100)
        $qEmpty = [Math]::Max(0, $width - $qFilled)
        $qBarColor = Get-QuotaColor -pct $clampedPct
        $fStr = [string]::new($charCircleFull, $qFilled)
        $eStr = [string]::new($charCircleEmpty, $qEmpty)
        return "$qBarColor$fStr$FG_GRAY$eStr$R"
    }

    function Get-QuotaLine {
        param(
            [string]$label,
            $quotaData,
            [string]$timeFormat
        )
        if ($null -eq $quotaData) { return $null }
        try {
            $remaining = 1.0
            if ($null -ne $quotaData.remaining_fraction) {
                $remaining = Get-SafeDouble $quotaData.remaining_fraction 1.0
            }
            $pct = [int][Math]::Round((1.0 - $remaining) * 100)
            $pct = [Math]::Max(0, [Math]::Min(100, $pct))

            $qBar = Get-QuotaBar -pct $pct
            $pctFmt = "{0,3}" -f $pct
            $pColor = Get-QuotaColor -pct $pct

            $resetIso = if ($null -ne $quotaData.reset_time) { $quotaData.reset_time.ToString() } else { "" }
            $resetFmt = ""
            if (-not [string]::IsNullOrEmpty($resetIso) -and $resetIso -ne "null") {
                try {
                    $dateTime = [DateTimeOffset]::Parse($resetIso)
                    $localTime = $dateTime.LocalDateTime
                    $timeStr = $localTime.ToString($timeFormat).ToLower()
                    $resetFmt = " $FG_GRAY$charReset$R $FG_WHITE$timeStr$R"
                } catch {}
            }

            return "$FG_WHITE$label$R $qBar $pColor$pctFmt%$R$resetFmt"
        } catch {
            return $null
        }
    }

    $quotaLines = [System.Collections.Generic.List[string]]::new()

    if ($config.show_quota -and $null -ne $data.quota) {
        $quotaPool = "gemini"
        if ($modelId -like "*claude*" -or $modelId -like "*anthropic*" -or $modelId -like "*3p*") {
            $quotaPool = "3p"
        }

        $poolLabel = if ($quotaPool -eq "3p") { "claude" } else { "gemini" }

        if ($quotaPool -eq "3p") {
            $quotaData5h = [PSCustomObject]@{ remaining_fraction = $Q_3P_5H_REM; reset_time = $Q_3P_5H_RES }
            $quotaDataWk = [PSCustomObject]@{ remaining_fraction = $Q_3P_WK_REM; reset_time = $Q_3P_WK_RES }
        } else {
            $quotaData5h = [PSCustomObject]@{ remaining_fraction = $Q_GEMINI_5H_REM; reset_time = $Q_GEMINI_5H_RES }
            $quotaDataWk = [PSCustomObject]@{ remaining_fraction = $Q_GEMINI_WK_REM; reset_time = $Q_GEMINI_WK_RES }
        }

        $line5h = Get-QuotaLine -label "$poolLabel 5h" -quotaData $quotaData5h -timeFormat "HH:mm"
        if ($null -ne $line5h) { $quotaLines.Add($line5h) }

        $lineWk = Get-QuotaLine -label "$poolLabel 7d" -quotaData $quotaDataWk -timeFormat "MMM d, HH:mm"
        if ($null -ne $lineWk) { $quotaLines.Add($lineWk) }
    }

    if (-not [string]::IsNullOrEmpty($planTier) -and $planTier -ne "null") {
        $quotaLines.Insert(0, "${FG_GRAY}plan:${R} $FG_WHITE$planTier$R")
    }

    # ─── Render Layout Based on Terminal Width ───────────────────────────────────
    $outLines = [System.Collections.Generic.List[string]]::new()
    if ($cols -ge $CONFIG_LAYOUT_WIDE_COLS) {
        $outLines.Add("$LINE1$FG_GRAY  $charPipe  $R$contextBarBadge")
        if ($allTelemetry.Count -gt 0) {
            $outLines.Add([string]::Join($pipeSep, $allTelemetry))
        }
    } elseif ($cols -ge $CONFIG_LAYOUT_MED_COLS) {
        $outLines.Add("$FG_GRAY$charCornerTop$charLine$R $LINE1")
        if ($allTelemetry.Count -gt 0) {
            $outLines.Add("$FG_GRAY$charJoin$charLine$R $contextBarBadge")
            $outLines.Add("$FG_GRAY$charCornerBot$charLine$R " + [string]::Join($dotSep, $allTelemetry))
        } else {
            $outLines.Add("$FG_GRAY$charCornerBot$charLine$R $contextBarBadge")
        }
    } else {
        $parts1A = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrEmpty($agentStateBadge)) { $parts1A.Add($agentStateBadge) }
        if (-not [string]::IsNullOrEmpty($modelDisplayName)) { $parts1A.Add("$FG_BRIGHT_MAGENTA$I$modelDisplayName$R") }
        $LINE1A = [string]::Join("$FG_GRAY $charSlash $R", $parts1A)

        $outLines.Add("$FG_GRAY$charCornerTop$charLine$R $LINE1A")
        $outLines.Add("$FG_GRAY$charJoin$charLine$R $gitDirStatusBadge")

        if ($telemetryParts.Count -gt 0 -and $extraParts.Count -gt 0) {
            $outLines.Add("$FG_GRAY$charJoin$charLine$R $contextBarBadge")
            $outLines.Add("$FG_GRAY$charJoin$charLine$R " + [string]::Join($dotSep, $telemetryParts))
            $outLines.Add("$FG_GRAY$charCornerBot$charLine$R " + [string]::Join($dotSep, $extraParts))
        } elseif ($allTelemetry.Count -gt 0) {
            $outLines.Add("$FG_GRAY$charJoin$charLine$R $contextBarBadge")
            $outLines.Add("$FG_GRAY$charCornerBot$charLine$R " + [string]::Join($dotSep, $allTelemetry))
        } else {
            $outLines.Add("$FG_GRAY$charCornerBot$charLine$R $contextBarBadge")
        }
    }

    foreach ($qLine in $quotaLines) {
        $outLines.Add($qLine)
    }

    foreach ($rawLine in $outLines) {
        Write-Output (Format-TruncatedAnsiLine -text $rawLine -maxCols $cols -resetSeq $R)
    }
} catch {
    Write-Output "agy (line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message))"
    exit 0
}
