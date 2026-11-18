#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/../bin/statusline.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

CONFIG_PATH="$HOME/.gemini/statusline.json"
CONFIG_BACKUP="$CONFIG_PATH.bak"
HAS_BACKUP=false

if [ -f "$CONFIG_PATH" ]; then
    cp "$CONFIG_PATH" "$CONFIG_BACKUP"
    HAS_BACKUP=true
fi

TEST_TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEST_TMP_DIR"
    if [ "$HAS_BACKUP" = true ]; then
        mv "$CONFIG_BACKUP" "$CONFIG_PATH"
    elif [ -f "$CONFIG_PATH" ]; then
        rm "$CONFIG_PATH"
    fi
}
trap cleanup EXIT

write_cfg() {
    mkdir -p "$(dirname "$CONFIG_PATH")"
    cat <<EOF >"$CONFIG_PATH"
{
  "show_quota": $1,
  "show_additional_stats": $2,
  "hide_zero_stats": $3,
  "show_state_indicator": $4
}
EOF
}

strip_ansi() {
    LC_ALL=C awk '{ gsub(/\033\[[0-9;]*[A-Za-z]/, ""); print }'
}

max_line_width() {
    LC_ALL=C awk '
    BEGIN {
        for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
        maxw = 0
    }
    function char_width(cp) {
        if (cp >= 65024 && cp <= 65039) return 0
        if (cp == 8205) return 0
        if (cp == 8986 || cp == 8987) return 2
        if ((cp >= 11904 && cp <= 40959) || (cp >= 63744 && cp <= 64255) || (cp >= 65072 && cp <= 65135) || (cp >= 65280 && cp <= 65519)) return 2
        return 1
    }
    {
        gsub(/\033\[[0-9;]*[A-Za-z]/, "")
        s = $0; n = length(s); i = 1; vis = 0
        while (i <= n) {
            b = ord[substr(s, i, 1)]
            if (b < 128) { cw = (b >= 32) ? 1 : 0; step = 1 }
            else if (b >= 194 && b <= 223 && i + 1 <= n) {
                b2 = ord[substr(s, i + 1, 1)]
                cw = char_width((b - 192) * 64 + (b2 - 128)); step = 2
            } else if (b >= 224 && b <= 239 && i + 2 <= n) {
                b2 = ord[substr(s, i + 1, 1)]; b3 = ord[substr(s, i + 2, 1)]
                cw = char_width((b - 224) * 4096 + (b2 - 128) * 64 + (b3 - 128)); step = 3
            } else if (b >= 240 && b <= 247 && i + 3 <= n) {
                cw = 2; step = 4
            } else { cw = 1; step = 1 }
            vis += cw; i += step
        }
        if (vis > maxw) maxw = vis
    }
    END { print maxw }'
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if ! printf "%s\n" "$haystack" | grep -Fq -- "$needle"; then
        echo "ASSERTION FAILED [$label]: expected output to contain '$needle'" >&2
        printf "%s\n" "$haystack" >&2
        exit 1
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if printf "%s\n" "$haystack" | grep -Fq -- "$needle"; then
        echo "ASSERTION FAILED [$label]: expected output NOT to contain '$needle'" >&2
        printf "%s\n" "$haystack" >&2
        exit 1
    fi
}

assert_width_and_no_trailing_blank() {
    local out="$1" max_cols="$2" label="$3"
    local plain
    plain=$(printf "%s\n" "$out" | strip_ansi)
    local last_line
    last_line=$(printf "%s\n" "$plain" | tail -n 1)
    if [ -z "$last_line" ]; then
        echo "ASSERTION FAILED [$label]: unexpected trailing blank line" >&2
        exit 1
    fi
    local observed
    observed=$(printf "%s\n" "$out" | max_line_width)
    if [ "$observed" -gt "$max_cols" ]; then
        echo "ASSERTION FAILED [$label]: line width $observed exceeds max $max_cols" >&2
        printf "%s\n" "$plain" >&2
        exit 1
    fi
}

run_fixture_test() {
    local fixture_name=$1
    write_cfg "$2" "$3" "$4" "$5"

    local fixture_path="$FIXTURES_DIR/$fixture_name.json"
    [ -f "$fixture_path" ] || { echo "Fixture not found: $fixture_path"; exit 1; }

    local out
    out=$(bash "$SCRIPT_PATH" <"$fixture_path")
    echo -e "\n\033[36m[TEST] $fixture_name\033[0m"
    printf "%s\n" "$out"

    local cols
    cols=$(jq -r '.terminal_width // 80' "$fixture_path" 2>/dev/null | tr -d '\r' || echo 80)
    if [ "$fixture_name" != "empty" ] && [ "$fixture_name" != "malformed" ]; then
        assert_width_and_no_trailing_blank "$out" "$cols" "$fixture_name"
    fi
}

# Standard fixtures
run_fixture_test "idle" true true true true
run_fixture_test "active_working" true true true true
run_fixture_test "claude_quota" true true true true
run_fixture_test "gemini_quota" true true true true
run_fixture_test "tool_use" true true true true
run_fixture_test "narrow_with_stats" true true true true
run_fixture_test "long_session" true true true true
run_fixture_test "empty" true true true true
run_fixture_test "malformed" true true true true
run_fixture_test "idle" true true false true
run_fixture_test "claude_quota" false true true true
run_fixture_test "active_working" true false true true
run_fixture_test "active_working" true true true false

# Regression 1: Non-git cwd must not collapse to "agy"
write_cfg true true true true
non_git_dir="$TEST_TMP_DIR/plain_workspace"
mkdir -p "$non_git_dir"
non_git_payload=$(jq -n --arg cwd "$non_git_dir" '{agent_state:"idle", cwd:$cwd, model:{id:"gemini-4", display_name:"Gemini 4"}, context_window:{used_percentage:10, context_window_size:1000000}, terminal_width:120}')
non_git_out=$(printf "%s" "$non_git_payload" | bash "$SCRIPT_PATH")
non_git_plain=$(printf "%s\n" "$non_git_out" | strip_ansi)
assert_contains "$non_git_plain" "plain_workspace" "non_git"
assert_contains "$non_git_plain" "READY" "non_git"
assert_width_and_no_trailing_blank "$non_git_out" 120 "non_git"

# Regression 2: /antigravity/ -> /antigravity-cli/ rewrite + Ctx consistency + Turns/Compact/Sigma/Avg
mkdir -p "$TEST_TMP_DIR/antigravity-cli/brain/s1"
t_real="$TEST_TMP_DIR/antigravity-cli/brain/s1/transcript.jsonl"
t_fake="$TEST_TMP_DIR/antigravity/brain/s1/transcript.jsonl"
cat <<'EOF' >"$t_real"
{"step_index":1,"type":"USER_INPUT","created_at":"2026-11-18T04:00:00Z","content":"hi"}
{"step_index":2,"type":"PLANNER_RESPONSE","created_at":"2026-11-18T04:00:01Z","input_tokens":1000,"cache_read_tokens":50000,"output_tokens":500}
{"step_index":3,"type":"GENERIC","created_at":"2026-11-18T04:00:06Z","content":"tool"}
{"step_index":4,"type":"CHECKPOINT","created_at":"2026-11-18T04:00:07Z","content":"cp"}
{"step_index":5,"type":"PLANNER_RESPONSE","created_at":"2026-11-18T04:00:08Z","input_tokens":1000,"cache_read_tokens":10000,"output_tokens":200}
{"step_index":6,"type":"USER_INPUT","created_at":"2026-11-18T04:01:00Z","content":"next"}
{"step_index":7,"type":"PLANNER_RESPONSE","created_at":"2026-11-18T04:01:01Z","input_tokens":1000,"cache_read_tokens":45000,"output_tokens":400}
{"step_index":8,"type":"PLANNER_RESPONSE","created_at":"2026-11-18T04:01:05Z","input_tokens":1000,"cache_read_tokens":5000,"output_tokens":100}
EOF

long_payload=$(jq -n --arg cwd "$non_git_dir" --arg tp "$t_fake" '{
  agent_state:"working",
  cwd:$cwd,
  transcript_path:$tp,
  model:{id:"gemini-4", display_name:"Gemini 4 Hydrogen (High)"},
  context_window:{
    context_window_size:1048576,
    used_percentage:15.0,
    total_input_tokens:900000,
    total_output_tokens:260000,
    current_usage:{input_tokens:2500, cache_creation_input_tokens:0, cache_read_input_tokens:154786}
  },
  terminal_width:140
}')
long_out=$(printf "%s" "$long_payload" | bash "$SCRIPT_PATH")
long_plain=$(printf "%s\n" "$long_out" | strip_ansi)
assert_contains "$long_plain" "Ctx: 157.3k/1.05M (15.0%)" "ctx_consistency"
assert_not_contains "$long_plain" "1.16M/1.05M" "ctx_no_mismatch"
assert_contains "$long_plain" "Turns: 2 (Compact: 2)" "turns_and_compact"
assert_contains "$long_plain" "Cache: 98.4% (154.8k)" "cache_rate"
assert_contains "$long_plain" "ΣTok: 115.2k" "sigma_tok"
assert_contains "$long_plain" "Avg: ~100 tok/s" "avg_speed"
assert_width_and_no_trailing_blank "$long_out" 140 "long_session_transcript"

# Regression 3: Missing transcript must NOT fake ΣTok from total_in + total_out
no_t_out=$(bash "$SCRIPT_PATH" <"$FIXTURES_DIR/long_session.json")
no_t_plain=$(printf "%s\n" "$no_t_out" | strip_ansi)
assert_contains "$no_t_plain" "Ctx: 157.3k/1.05M (15.0%)" "no_transcript_ctx"
assert_not_contains "$no_t_plain" "ΣTok:" "no_fake_sigma"
assert_not_contains "$no_t_plain" "Turns:" "no_fake_turns"

echo -e "\n\033[32m[SUCCESS] All statusline.sh assertions passed!\033[0m"
