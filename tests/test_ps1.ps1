# Windows PowerShell test harness for statusline.ps1
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptPath = Join-Path $PSScriptRoot "..\bin\statusline.ps1"
$fixturesDir = Join-Path $PSScriptRoot "fixtures"

$configPath = Join-Path ([System.Environment]::GetFolderPath("UserProfile")) ".gemini\statusline.json"
$configBackup = "$configPath.bak"
$hasBackup = $false

if (Test-Path $configPath) {
    Copy-Item $configPath $configBackup -Force
    $hasBackup = $true
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("agy_test_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

function Write-TestConfig {
    param([hashtable]$Config)
    $geminiDir = [System.IO.Path]::GetDirectoryName($configPath)
    if (-not (Test-Path $geminiDir)) {
        New-Item -ItemType Directory -Path $geminiDir -Force | Out-Null
    }
    $cfgJson = ConvertTo-Json $Config
    [System.IO.File]::WriteAllText($configPath, $cfgJson, [System.Text.UTF8Encoding]::new($false))
}

function Strip-Ansi {
    param([string]$Text)
    return ([regex]::Replace($Text, '\x1b\[[0-9;]*[A-Za-z]', ''))
}

function Get-LineDisplayWidth {
    param([string]$PlainLine)
    $w = 0
    $enum = [System.Globalization.StringInfo]::GetTextElementEnumerator($PlainLine)
    while ($enum.MoveNext()) {
        $elem = $enum.GetTextElement()
        $cp = [char]::ConvertToUtf32($elem, 0)
        if (($cp -ge 0xFE00 -and $cp -le 0xFE0F) -or $cp -eq 0x200D -or $cp -lt 0x20) { continue }
        if (($cp -ge 0x1F300 -and $cp -le 0x1FAFF) -or $cp -eq 0x231A -or $cp -eq 0x231B -or
            ($cp -ge 0x2E80 -and $cp -le 0x9FFF) -or ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
            ($cp -ge 0xFE30 -and $cp -le 0xFE6F) -or ($cp -ge 0xFF00 -and $cp -le 0xFFEF)) {
            $w += 2
        } else {
            $w += 1
        }
    }
    return $w
}

function Invoke-StatuslineWithJson {
    param([string]$JsonPayload)
    $psi = [System.Diagnostics.ProcessStartInfo]::new("powershell", "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"")
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $sw = [System.IO.StreamWriter]::new($proc.StandardInput.BaseStream, [System.Text.UTF8Encoding]::new($false))
    $sw.Write($JsonPayload)
    $sw.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        throw "statusline.ps1 exited with $($proc.ExitCode): $stderr"
    }
    return $stdout.TrimEnd("`r", "`n")
}

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Label)
    if (-not $Text.Contains($Needle)) {
        throw "ASSERTION FAILED [$Label]: expected output to contain '$Needle'`nActual:`n$Text"
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Needle, [string]$Label)
    if ($Text.Contains($Needle)) {
        throw "ASSERTION FAILED [$Label]: expected output NOT to contain '$Needle'`nActual:`n$Text"
    }
}

function Assert-WidthAndNoTrailingBlank {
    param([string]$Output, [int]$MaxCols, [string]$Label)
    $lines = $Output -split "`r?`n"
    if ($lines.Count -eq 0 -or [string]::IsNullOrWhiteSpace((Strip-Ansi $lines[-1]))) {
        throw "ASSERTION FAILED [$Label]: unexpected trailing blank line"
    }
    foreach ($ln in $lines) {
        $plain = Strip-Ansi $ln
        $w = Get-LineDisplayWidth $plain
        if ($w -gt $MaxCols) {
            throw "ASSERTION FAILED [$Label]: line width $w exceeds max $MaxCols`: $plain"
        }
    }
}

function Run-FixtureTest {
    param(
        [string]$FixtureName,
        [hashtable]$Config
    )
    Write-Host "`n[TEST] $FixtureName" -ForegroundColor Cyan
    Write-TestConfig $Config
    $fixturePath = Join-Path $fixturesDir "$FixtureName.json"
    if (-not (Test-Path $fixturePath)) { throw "Fixture not found: $fixturePath" }
    $raw = [System.IO.File]::ReadAllText($fixturePath, [System.Text.Encoding]::UTF8)
    $out = Invoke-StatuslineWithJson $raw
    Write-Host $out

    if ($FixtureName -ne "empty" -and $FixtureName -ne "malformed") {
        $obj = ConvertFrom-Json $raw
        $cols = if ($null -ne $obj.terminal_width) { [int]$obj.terminal_width } else { 80 }
        Assert-WidthAndNoTrailingBlank $out $cols $FixtureName
    }
}

try {
    $defaultConfig = @{
        show_quota = $true
        show_additional_stats = $true
        hide_zero_stats = $true
        show_state_indicator = $true
    }
    Run-FixtureTest "idle" $defaultConfig
    Run-FixtureTest "active_working" $defaultConfig
    Run-FixtureTest "claude_quota" $defaultConfig
    Run-FixtureTest "gemini_quota" $defaultConfig
    Run-FixtureTest "tool_use" $defaultConfig
    Run-FixtureTest "narrow_with_stats" $defaultConfig
    Run-FixtureTest "long_session" $defaultConfig
    Run-FixtureTest "empty" $defaultConfig
    Run-FixtureTest "malformed" $defaultConfig

    Run-FixtureTest "idle" @{ show_quota = $true; show_additional_stats = $true; hide_zero_stats = $false; show_state_indicator = $true }
    Run-FixtureTest "claude_quota" @{ show_quota = $false; show_additional_stats = $true; hide_zero_stats = $true; show_state_indicator = $true }
    Run-FixtureTest "active_working" @{ show_quota = $true; show_additional_stats = $false; hide_zero_stats = $true; show_state_indicator = $true }
    Run-FixtureTest "active_working" @{ show_quota = $true; show_additional_stats = $true; hide_zero_stats = $true; show_state_indicator = $false }

    # Regression 1: Non-git directory
    Write-TestConfig $defaultConfig
    $nonGitDir = Join-Path $tempDir "plain_workspace"
    New-Item -ItemType Directory -Path $nonGitDir -Force | Out-Null
    $nonGitJson = @{
        agent_state = "idle"
        cwd = $nonGitDir
        model = @{ id = "gemini-4"; display_name = "Gemini 4" }
        context_window = @{ used_percentage = 10; context_window_size = 1000000 }
        terminal_width = 120
    } | ConvertTo-Json -Depth 5
    $nonGitOut = Strip-Ansi (Invoke-StatuslineWithJson $nonGitJson)
    Assert-Contains $nonGitOut "plain_workspace" "non_git"
    Assert-Contains $nonGitOut "READY" "non_git"

    # Regression 2: \antigravity\ -> \antigravity-cli\ rewrite + Ctx consistency + Turns/Compact/Sigma/Avg
    $realDir = Join-Path $tempDir "antigravity-cli\brain\s1"
    New-Item -ItemType Directory -Path $realDir -Force | Out-Null
    $tReal = Join-Path $realDir "transcript.jsonl"
    $tFake = Join-Path $tempDir "antigravity\brain\s1\transcript.jsonl"
    $transcriptLines = @(
        '{"step_index":1,"type":"USER_INPUT","created_at":"2026-11-18T04:00:00Z","content":"hi"}',
        '{"step_index":2,"type":"PLANNER_RESPONSE","created_at":"2026-11-18T04:00:01Z","input_tokens":1000,"cache_read_tokens":50000,"output_tokens":500}',
        '{"step_index":3,"type":"GENERIC","created_at":"2026-11-18T04:00:06Z","content":"tool"}',
        '{"step_index":4,"type":"CHECKPOINT","created_at":"2026-11-18T04:00:07Z","content":"cp"}',
        '{"step_index":5,"type":"PLANNER_RESPONSE","created_at":"2026-11-18T04:00:08Z","input_tokens":1000,"cache_read_tokens":10000,"output_tokens":200}',
        '{"step_index":6,"type":"USER_INPUT","created_at":"2026-11-18T04:01:00Z","content":"next"}',
        '{"step_index":7,"type":"PLANNER_RESPONSE","created_at":"2026-11-18T04:01:01Z","input_tokens":1000,"cache_read_tokens":45000,"output_tokens":400}',
        '{"step_index":8,"type":"PLANNER_RESPONSE","created_at":"2026-11-18T04:01:05Z","input_tokens":1000,"cache_read_tokens":5000,"output_tokens":100}'
    )
    [System.IO.File]::WriteAllLines($tReal, $transcriptLines, [System.Text.UTF8Encoding]::new($false))

    $longPayload = @{
        agent_state = "working"
        cwd = $nonGitDir
        transcript_path = $tFake
        model = @{ id = "gemini-4"; display_name = "Gemini 4 Hydrogen (High)" }
        context_window = @{
            context_window_size = 1048576
            used_percentage = 15.0
            total_input_tokens = 900000
            total_output_tokens = 260000
            current_usage = @{ input_tokens = 2500; cache_creation_input_tokens = 0; cache_read_input_tokens = 154786 }
        }
        terminal_width = 140
    } | ConvertTo-Json -Depth 6
    $longRawOut = Invoke-StatuslineWithJson $longPayload
    $longPlain = Strip-Ansi $longRawOut
    Assert-Contains $longPlain "Ctx: 157.3k/1.05M (15.0%)" "ctx_consistency"
    Assert-NotContains $longPlain "1.16M/1.05M" "ctx_no_mismatch"
    Assert-Contains $longPlain "Turns: 2 (Compact: 2)" "turns_and_compact"
    Assert-Contains $longPlain "Cache: 98.4% (154.8k)" "cache_rate"
    Assert-Contains $longPlain "Tok: 115.2k" "sigma_tok"
    Assert-Contains $longPlain "Avg: ~100 tok/s" "avg_speed"
    Assert-WidthAndNoTrailingBlank $longRawOut 140 "long_session_transcript"

    # Regression 3: Missing transcript must NOT fake SigmaTok
    $noTPayload = [System.IO.File]::ReadAllText((Join-Path $fixturesDir "long_session.json"), [System.Text.Encoding]::UTF8)
    $noTPlain = Strip-Ansi (Invoke-StatuslineWithJson $noTPayload)
    Assert-Contains $noTPlain "Ctx: 157.3k/1.05M (15.0%)" "no_transcript_ctx"
    Assert-NotContains $noTPlain "Tok:" "no_fake_sigma"
    Assert-NotContains $noTPlain "Turns:" "no_fake_turns"

    Write-Host "`n[SUCCESS] All statusline.ps1 assertions passed!" -ForegroundColor Green
}
finally {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($hasBackup) {
        Move-Item $configBackup $configPath -Force
    } elseif (Test-Path $configPath) {
        Remove-Item $configPath -Force
    }
}
