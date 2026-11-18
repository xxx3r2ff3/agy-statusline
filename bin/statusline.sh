#!/bin/bash
set -f

# ─── Ensure graceful failure ──────────────────────────────────────────────────
trap 'printf "agy\n"; exit 0' ERR

# ─── Read Stdin ─────────────────────────────────────────────────────────────
input=$(cat)
if [ -z "$input" ]; then
    printf "agy"
    exit 0
fi

# ─── Parse JSON from stdin (Single jq pass for performance) ──────────────────
{
    read -r STATE
    read -r USED_PCT
    read -r CTX_MAX_TOK
    read -r TOTAL_IN_TOK
    read -r TOTAL_OUT_TOK
    read -r CUR_IN_TOK
    read -r CUR_CACHE_CREATE
    read -r CUR_CACHE_READ
    read -r TRANSCRIPT_PATH
    read -r VCS_BRANCH
    read -r VCS_DIRTY
    read -r SANDBOX
    read -r ARTIFACTS
    read -r SUBAGENTS
    read -r BG_TASKS
    read -r MODEL_NAME
    read -r MODEL_ID
    read -r PLAN_TIER
    read -r COLS
    read -r CWD
    read -r Q_3P_5H_REM
    read -r Q_3P_5H_RESET
    read -r Q_3P_WK_REM
    read -r Q_3P_WK_RESET
    read -r Q_GEM_5H_REM
    read -r Q_GEM_5H_RESET
    read -r Q_GEM_WK_REM
    read -r Q_GEM_WK_RESET
} <<<"$(
    jq -r '
    (.agent_state // "idle"),
    (.context_window?.used_percentage? // 0),
    (.context_window?.context_window_size? // 0),
    (.context_window?.total_input_tokens? // 0),
    (.context_window?.total_output_tokens? // 0),
    (.context_window?.current_usage?.input_tokens? // 0),
    (.context_window?.current_usage?.cache_creation_input_tokens? // 0),
    (.context_window?.current_usage?.cache_read_input_tokens? // 0),
    (.transcript_path // ""),
    (.vcs?.branch? // ""),
    (.vcs?.dirty? // false),
    (.sandbox?.enabled? // false),
    (.artifact_count // 0),
    (if (.subagents | type) == "array" then (.subagents | length) else 0 end),
    (.task_count // 0),
    (.model?.display_name? // ""),
    (.model?.id? // ""),
    (.plan_tier // ""),
    (.terminal_width // 80),
    (.cwd // ""),
    (.quota?["3p-5h"]?.remaining_fraction? // "null"),
    (.quota?["3p-5h"]?.reset_time? // "null"),
    (.quota?["3p-weekly"]?.remaining_fraction? // "null"),
    (.quota?["3p-weekly"]?.reset_time? // "null"),
    (.quota?["gemini-5h"]?.remaining_fraction? // "null"),
    (.quota?["gemini-5h"]?.reset_time? // "null"),
    (.quota?["gemini-weekly"]?.remaining_fraction? // "null"),
    (.quota?["gemini-weekly"]?.reset_time? // "null")
  ' <<<"$input" 2>/dev/null || printf "idle\n0\n0\n0\n0\n0\n0\n0\n\n\nfalse\nfalse\n0\n0\n0\n\n\n\n80\n\nnull\nnull\nnull\nnull\nnull\nnull\nnull\nnull\n"
)"

# ─── Configuration Constants ──────────────────────────────────────────────────
CONFIG_LAYOUT_WIDE_COLS=120
CONFIG_LAYOUT_MED_COLS=100
CONFIG_BAR_LEN_CTX=15
charSlash="/"
charPipe="│"
charSigma="Σ"
CONFIG_BAR_LEN_QUOTA=10
CONFIG_CTX_WARN_PCT=60
CONFIG_CTX_CRIT_PCT=90
CONFIG_QUOTA_INFO_PCT=50
CONFIG_QUOTA_WARN_PCT=70
CONFIG_QUOTA_CRIT_PCT=90

# ─── Configuration Loader (Optional ~/.gemini/statusline.json) ───────────────
CONFIG_PATH="$HOME/.gemini/statusline.json"
show_quota=true
show_additional_stats=true
hide_zero_stats=true
show_state_indicator=true

if [ -f "$CONFIG_PATH" ]; then
    {
        read -r cfg_quota
        read -r cfg_stats
        read -r cfg_hide_zero
        read -r cfg_state
    } <<<"$(
        jq -r '
          (if .show_quota == null then true else .show_quota end),
          (if .show_additional_stats == null then true else .show_additional_stats end),
          (if .hide_zero_stats == null then true else .hide_zero_stats end),
          (if .show_state_indicator == null then true else .show_state_indicator end)
        ' "$CONFIG_PATH" 2>/dev/null || printf "true\ntrue\ntrue\ntrue\n"
    )"
    [ "$cfg_quota" = "false" ] && show_quota=false
    [ "$cfg_stats" = "false" ] && show_additional_stats=false
    [ "$cfg_hide_zero" = "false" ] && hide_zero_stats=false
    [ "$cfg_state" = "false" ] && show_state_indicator=false
fi

# ─── ANSI Colors & Formatting (Standard 16 colors) ───────────────────────────
R="\033[0m" # Reset
B="\033[1m" # Bold
I="\033[3m" # Italic
# D="\033[2m"         # Dim (uncomment for custom theming)
# FG_GREEN="\033[32m"
# FG_YELLOW="\033[33m"
# FG_CYAN="\033[36m"
# FG_MAGENTA="\033[35m"
FG_WHITE="\033[37m"
FG_GRAY="\033[90m"
FG_BRIGHT_RED="\033[91m"
FG_BRIGHT_GREEN="\033[92m"
FG_BRIGHT_YELLOW="\033[93m"
FG_BRIGHT_BLUE="\033[94m"
FG_BRIGHT_MAGENTA="\033[95m"
FG_BRIGHT_CYAN="\033[96m"
FG_BRIGHT_WHITE="\033[97m"

NUM_COLOR="${FG_BRIGHT_WHITE}${B}"

# Resolve CWD basename
if [ -z "$CWD" ] || [ "$CWD" = "null" ]; then
    CWD=$(pwd)
fi
DIRNAME=$(basename "$CWD")

# ─── Fallback Git Branch Detection ───────────────────────────────────────────
if [ -z "$VCS_BRANCH" ] || [ "$VCS_BRANCH" = "null" ]; then
    if [ -n "$CWD" ] && [ -d "$CWD" ]; then
        git_branch=$(git -C "$CWD" branch --show-current 2>/dev/null)
        if [ -n "$git_branch" ]; then
            VCS_BRANCH="$git_branch"
            git_status=$(git -C "$CWD" status --porcelain 2>/dev/null)
            if [ -n "$git_status" ]; then
                VCS_DIRTY="true"
            else
                VCS_DIRTY="false"
            fi
        fi
    fi
fi

# ─── Helpers ─────────────────────────────────────────────────────────────────
format_tok() {
    LC_NUMERIC=C awk -v n="${1:-0}" 'BEGIN {
        if (n >= 1000000) printf "%.2fM", n / 1000000
        else if (n >= 1000) printf "%.1fk", n / 1000
        else printf "%.0f", n
    }'
}

normalize_transcript_path() {
    local p="$1"
    if [ -z "$p" ] || [ "$p" = "null" ]; then
        return
    fi
    case "$p" in
        file://*) p="${p#file://}" ;;
    esac
    case "$p" in
        "~") p="$HOME" ;;
        "~/"*) p="$HOME/${p#~/}" ;;
    esac
    if [ ! -f "$p" ]; then
        local alt="${p/\/antigravity\//\/antigravity-cli\/}"
        if [ -f "$alt" ]; then
            p="$alt"
        fi
    fi
    printf "%s" "$p"
}

parse_transcript_metrics() {
    local tpath="$1"
    if [ -z "$tpath" ] || [ ! -f "$tpath" ]; then
        printf "0 0 0 0\n"
        return
    fi
    LC_NUMERIC=C awk '
    function json_str(s, key,    pat, idx, rest, q) {
        pat = "\"" key "\":\""
        idx = index(s, pat)
        if (idx == 0) return ""
        rest = substr(s, idx + length(pat))
        q = index(rest, "\"")
        if (q == 0) return ""
        return substr(rest, 1, q - 1)
    }
    function json_num(s, key,    pat, idx, rest) {
        pat = "\"" key "\":"
        idx = index(s, pat)
        if (idx == 0) return 0
        rest = substr(s, idx + length(pat))
        return rest + 0
    }
    function iso_to_epoch(ts,    y, m, d, H, M, S, y_adj, era, yoe, m_adj, doy, doe, days, tail, tz_pos, tz_sign, tz_h, tz_m, tz_off) {
        if (length(ts) < 19) return -1
        y = substr(ts, 1, 4) + 0
        m = substr(ts, 6, 2) + 0
        d = substr(ts, 9, 2) + 0
        H = substr(ts, 12, 2) + 0
        M = substr(ts, 15, 2) + 0
        S = substr(ts, 18) + 0
        if (y < 1970 || m < 1 || m > 12 || d < 1 || d > 31) return -1
        tz_off = 0
        tail = substr(ts, 20)
        tz_pos = index(tail, "+")
        tz_sign = 1
        if (tz_pos == 0) {
            tz_pos = index(tail, "-")
            tz_sign = -1
        }
        if (tz_pos > 0) {
            tz_h = substr(tail, tz_pos + 1, 2) + 0
            tz_m = substr(tail, tz_pos + 4, 2) + 0
            tz_off = tz_sign * (tz_h * 3600 + tz_m * 60)
        }
        y_adj = y - (m <= 2 ? 1 : 0)
        era = int(y_adj / 400)
        yoe = y_adj - era * 400
        m_adj = m + (m > 2 ? -3 : 9)
        doy = int((153 * m_adj + 2) / 5) + d - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        days = era * 146097 + doe - 719468
        return days * 86400 + H * 3600 + M * 60 + S - tz_off
    }
    BEGIN {
        turns = 0
        compacts = 0
        sigma = 0
        prev_ctx = 0
        prev_planner = 0
        prev_out = 0
        prev_ts = -1
        n_samples = 0
    }
    {
        head = (length($0) > 400) ? substr($0, 1, 400) : $0
        stype = json_str(head, "type")
        if (stype == "") next
        ts_str = json_str(head, "created_at")
        ts = (ts_str != "") ? iso_to_epoch(ts_str) : -1
        if (prev_planner && stype == "GENERIC" && ts >= 0 && prev_ts >= 0) {
            dt = ts - prev_ts
            if (dt >= 1.0 && dt <= 120.0 && prev_out > 0) {
                n_samples++
                samp_out[n_samples] = prev_out
                samp_dt[n_samples] = dt
            }
        }
        prev_planner = 0
        if (stype == "CHECKPOINT" || stype == "COMPACT") {
            compacts++
        } else if (stype == "PLANNER_RESPONSE") {
            turns++
            s_in = json_num(head, "input_tokens")
            s_cr = json_num(head, "cache_read_tokens")
            s_out = json_num(head, "output_tokens")
            sigma += s_in + s_cr + s_out
            cur_ctx = s_in + s_cr
            if (prev_ctx > 0 && (prev_ctx - cur_ctx) > 30000) {
                compacts++
            }
            prev_ctx = cur_ctx
            prev_planner = 1
            prev_out = s_out
            prev_ts = ts
        }
    }
    END {
        avg_tps = 0
        if (n_samples > 0) {
            start_idx = (n_samples > 10) ? (n_samples - 9) : 1
            sum_out = 0
            sum_dt = 0
            for (i = start_idx; i <= n_samples; i++) {
                sum_out += samp_out[i]
                sum_dt += samp_dt[i]
            }
            if (sum_dt > 0) avg_tps = sum_out / sum_dt
        }
        printf "%d %d %.0f %.6f\n", turns, compacts, sigma, avg_tps
    }' "$tpath" 2>/dev/null || printf "0 0 0 0\n"
}

color_for_pct() {
    local pct=$1
    if [ "$pct" -ge "$CONFIG_QUOTA_CRIT_PCT" ]; then
        printf "%b" "$FG_BRIGHT_RED"
    elif [ "$pct" -ge "$CONFIG_QUOTA_WARN_PCT" ]; then
        printf "%b" "$FG_BRIGHT_YELLOW"
    elif [ "$pct" -ge "$CONFIG_QUOTA_INFO_PCT" ]; then
        printf "%b" "$FG_BRIGHT_CYAN"
    else
        printf "%b" "$FG_BRIGHT_GREEN"
    fi
}

build_quota_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(((pct * width) / 100))
    local empty=$((width - filled))
    local bar_color
    bar_color=$(color_for_pct "$pct")

    local filled_str="" empty_str=""
    for ((i = 0; i < filled; i++)); do filled_str+="●"; done
    for ((i = 0; i < empty; i++)); do empty_str+="○"; done

    printf "%b" "${bar_color}${filled_str}${FG_GRAY}${empty_str}${R}"
}

format_reset_time() {
    local reset_iso=$1
    local style=$2 # "time" or "datetime"
    [ -z "$reset_iso" ] || [ "$reset_iso" = "null" ] && return

    local epoch=""
    if date -d "$reset_iso" +%s >/dev/null 2>&1; then
        epoch=$(date -d "$reset_iso" +%s 2>/dev/null)
    elif date -j -f "%Y-%m-%dT%H:%M:%SZ" "$reset_iso" +%s >/dev/null 2>&1; then
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$reset_iso" +%s 2>/dev/null)
    elif date -j -f "%Y-%m-%dT%H:%M:%S%z" "$reset_iso" +%s >/dev/null 2>&1; then
        local clean_iso
        # Strip colon from ISO-8601 offset for BSD date (%z requires no colon)
        clean_iso="${reset_iso%:*}${reset_iso##*:}"
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$clean_iso" +%s 2>/dev/null)
    fi

    [ -z "$epoch" ] && return

    local result=""
    if date --version >/dev/null 2>&1; then
        if [ "$style" = "time" ]; then
            result=$(date -d "@$epoch" +"%H:%M" 2>/dev/null)
        else
            result=$(date -d "@$epoch" +"%b %-d, %H:%M" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        fi
    else
        if [ "$style" = "time" ]; then
            result=$(date -r "$epoch" +"%H:%M" 2>/dev/null)
        else
            result=$(date -r "$epoch" +"%b %e, %H:%M" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/  */ /g')
        fi
    fi

    printf "%s" "$result"
}

format_quota_line() {
    local label="$1"
    local rem="$2"
    local reset="$3"
    local style="$4"

    if [ -z "$rem" ] || [ "$rem" = "null" ]; then
        return 1
    fi

    local pct
    pct=$(LC_NUMERIC=C echo "$rem" | awk '{printf "%.0f", (1 - $1) * 100}' 2>/dev/null || echo 0)
    local qBar
    qBar=$(build_quota_bar "$pct" "$CONFIG_BAR_LEN_QUOTA")
    local pct_fmt
    pct_fmt=$(LC_NUMERIC=C printf "%3d" "$pct")
    local reset_fmt
    reset_fmt=$(format_reset_time "$reset" "$style")
    local pColor
    pColor=$(color_for_pct "$pct")

    local line="${FG_WHITE}${label}${R} ${qBar} ${pColor}${pct_fmt}%${R}"
    if [ -n "$reset_fmt" ]; then
        line+=" ${FG_GRAY}⟳${R} ${FG_WHITE}${reset_fmt}${R}"
    fi
    echo "$line"
    return 0
}

# ─── LINE 1: State, Model, VCS Branch, Plan ──────────────────────────────────
S=""
if [ "$show_state_indicator" = true ]; then
    case "$STATE" in
        idle) S="${FG_BRIGHT_GREEN}${B}● READY${R}" ;;
        thinking) S="${FG_BRIGHT_YELLOW}${B}◆ THINKING${R}" ;;
        working) S="${FG_BRIGHT_CYAN}${B}⚙ WORKING${R}" ;;
        tool_use) S="${FG_BRIGHT_MAGENTA}${B}🔧 TOOL${R}" ;;
        *) S="${FG_WHITE}${B}⏳ $(echo "$STATE" | tr '[:lower:]' '[:upper:]')${R}" ;;
    esac
fi

DBlock="${FG_BRIGHT_CYAN}${DIRNAME}${R}"
if [ -n "$VCS_BRANCH" ] && [ "$VCS_BRANCH" != "null" ]; then
    if [ "$VCS_DIRTY" = "true" ]; then
        DBlock+=" ${FG_BRIGHT_GREEN}(${FG_BRIGHT_RED}${VCS_BRANCH}${FG_BRIGHT_YELLOW}*${FG_BRIGHT_GREEN})${R}"
    else
        DBlock+=" ${FG_BRIGHT_GREEN}(${FG_BRIGHT_BLUE}${VCS_BRANCH}${FG_BRIGHT_GREEN})${R}"
    fi
fi

parts=()
[ -n "$S" ] && parts+=("$S")
[ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "null" ] && parts+=("${FG_BRIGHT_MAGENTA}${I}${MODEL_NAME}${R}")
[ -n "$DBlock" ] && parts+=("$DBlock")

LINE1=""
for ((i = 0; i < ${#parts[@]}; i++)); do
    if [ "$i" -gt 0 ]; then
        LINE1+="${FG_GRAY} ${charSlash} ${R}"
    fi
    LINE1+="${parts[$i]}"
done

# ─── LINE 2: Context Bar & Stats ─────────────────────────────────────────────
read -r CTX_USED_TOK CACHE_DENOM CACHE_PCT <<<"$(
    LC_NUMERIC=C awk -v max_tok="$CTX_MAX_TOK" -v used_pct="$USED_PCT" \
        -v tot_in="$TOTAL_IN_TOK" -v tot_out="$TOTAL_OUT_TOK" \
        -v cur_in="$CUR_IN_TOK" -v cur_cc="$CUR_CACHE_CREATE" -v cur_cr="$CUR_CACHE_READ" '
    BEGIN {
        host_used = tot_in + tot_out
        prompt_tok = cur_in + cur_cc + cur_cr
        ctx_used = (host_used > 0) ? host_used : prompt_tok
        if (ctx_used <= 0 && max_tok > 0 && used_pct > 0) {
            ctx_used = max_tok * used_pct / 100.0
        }
        cache_pct = (prompt_tok > 0) ? (cur_cr * 100.0 / prompt_tok) : 0
        printf "%.0f %.0f %.6f\n", ctx_used, prompt_tok, cache_pct
    }'
)"

NORM_TRANSCRIPT_PATH=$(normalize_transcript_path "$TRANSCRIPT_PATH")
read -r TURNS_COUNT COMPACT_COUNT SIGMA_TOKENS AVG_TOK_PER_SEC <<<"$(parse_transcript_metrics "$NORM_TRANSCRIPT_PATH")"

if LC_NUMERIC=C awk -v s="$SIGMA_TOKENS" 'BEGIN { exit !(s <= 0) }'; then
    SIGMA_TOKENS=$(LC_NUMERIC=C awk -v tot_in="$TOTAL_IN_TOK" -v tot_out="$TOTAL_OUT_TOK" -v ctx_used="$CTX_USED_TOK" '
    BEGIN {
        host_tot = tot_in + tot_out
        printf "%.0f", (host_tot > 0) ? host_tot : ctx_used
    }')
fi

PCT_INT=$(LC_NUMERIC=C printf "%.0f" "$USED_PCT" 2>/dev/null || echo 0)
FILLED=$(((PCT_INT * CONFIG_BAR_LEN_CTX) / 100))
REMAINDER=$(((PCT_INT * CONFIG_BAR_LEN_CTX) % 100))

if [ "$PCT_INT" -ge "$CONFIG_CTX_CRIT_PCT" ]; then
    BAR_COLOR="$FG_BRIGHT_RED"
elif [ "$PCT_INT" -ge "$CONFIG_CTX_WARN_PCT" ]; then
    BAR_COLOR="$FG_BRIGHT_YELLOW"
else
    BAR_COLOR="$FG_BRIGHT_WHITE"
fi

BAR=""
for ((i = 0; i < CONFIG_BAR_LEN_CTX; i++)); do
    if [ "$i" -lt "$FILLED" ]; then
        BAR="${BAR}█"
    elif [ "$i" -eq "$FILLED" ]; then
        if [ "$REMAINDER" -ge 75 ]; then
            BAR="${BAR}▓"
        elif [ "$REMAINDER" -ge 50 ]; then
            BAR="${BAR}▒"
        elif [ "$REMAINDER" -ge 25 ]; then
            BAR="${BAR}░"
        else
            BAR="${BAR}·"
        fi
    else
        BAR="${BAR}·"
    fi
done

PCT_FMT=$(LC_NUMERIC=C printf "%.1f" "$USED_PCT" 2>/dev/null || echo "0.0")
if LC_NUMERIC=C awk -v m="$CTX_MAX_TOK" 'BEGIN { exit !(m > 0) }'; then
    CTX_USED_FMT=$(format_tok "$CTX_USED_TOK")
    CTX_MAX_FMT=$(format_tok "$CTX_MAX_TOK")
    CTX="${FG_GRAY}Ctx: ${NUM_COLOR}${CTX_USED_FMT}${FG_GRAY}/${NUM_COLOR}${CTX_MAX_FMT} ${FG_GRAY}(${NUM_COLOR}${PCT_FMT}%${FG_GRAY}) ${BAR_COLOR}[${BAR}]${R}"
else
    CTX="${FG_GRAY}Ctx: ${BAR_COLOR}[${BAR}] ${NUM_COLOR}${PCT_FMT}%${R}"
fi

telemetry_parts=()
telemetry_parts+=("${FG_GRAY}Turns: ${NUM_COLOR}${TURNS_COUNT} ${FG_GRAY}(Compact: ${NUM_COLOR}${COMPACT_COUNT}${FG_GRAY})${R}")
if LC_NUMERIC=C awk -v d="$CACHE_DENOM" 'BEGIN { exit !(d > 0) }'; then
    CACHE_PCT_FMT=$(LC_NUMERIC=C printf "%.1f" "$CACHE_PCT" 2>/dev/null || echo "0.0")
    CACHE_READ_FMT=$(format_tok "$CUR_CACHE_READ")
    telemetry_parts+=("${FG_GRAY}Cache: ${NUM_COLOR}${CACHE_PCT_FMT}% ${FG_GRAY}(${NUM_COLOR}${CACHE_READ_FMT}${FG_GRAY})${R}")
fi
if LC_NUMERIC=C awk -v s="$SIGMA_TOKENS" 'BEGIN { exit !(s > 0) }'; then
    SIGMA_FMT=$(format_tok "$SIGMA_TOKENS")
    telemetry_parts+=("${FG_GRAY}${charSigma}Tok: ${NUM_COLOR}${SIGMA_FMT}${R}")
fi
if LC_NUMERIC=C awk -v a="$AVG_TOK_PER_SEC" 'BEGIN { exit !(a > 0) }'; then
    AVG_FMT=$(LC_NUMERIC=C printf "%.0f" "$AVG_TOK_PER_SEC" 2>/dev/null || echo "0")
    telemetry_parts+=("${FG_GRAY}Avg: ${NUM_COLOR}~${AVG_FMT} tok/s${R}")
fi

if [ "$show_additional_stats" = true ]; then
    if [ "$hide_zero_stats" = false ] || [ "$ARTIFACTS" -gt 0 ]; then
        telemetry_parts+=("${FG_GRAY}artifacts ${NUM_COLOR}${ARTIFACTS}${R}")
    fi
    if [ "$hide_zero_stats" = false ] || [ "$SUBAGENTS" -gt 0 ]; then
        telemetry_parts+=("${FG_GRAY}subagents ${NUM_COLOR}${SUBAGENTS}${R}")
    fi
    if [ "$hide_zero_stats" = false ] || [ "$BG_TASKS" -gt 0 ]; then
        telemetry_parts+=("${FG_GRAY}tasks ${NUM_COLOR}${BG_TASKS}${R}")
    fi
    if [ "$SANDBOX" = "true" ]; then
        telemetry_parts+=("${FG_GRAY}sandbox ${FG_BRIGHT_GREEN}${B}ON${R}")
    elif [ "$hide_zero_stats" = false ]; then
        telemetry_parts+=("${FG_GRAY}sandbox off${R}")
    fi
fi

PIPE_SEP="${FG_GRAY} ${charPipe} ${R}"
LINE_TELEMETRY=""
for ((i = 0; i < ${#telemetry_parts[@]}; i++)); do
    if [ "$i" -gt 0 ]; then
        LINE_TELEMETRY+="$PIPE_SEP"
    fi
    LINE_TELEMETRY+="${telemetry_parts[$i]}"
done

stat_parts=()
stat_parts+=("$CTX")
for tp in "${telemetry_parts[@]}"; do
    stat_parts+=("$tp")
done

DOT="${FG_GRAY} · ${R}"
LINE2=" "
for ((i = 0; i < ${#stat_parts[@]}; i++)); do
    if [ "$i" -gt 0 ]; then
        LINE2+="$DOT"
    fi
    LINE2+="${stat_parts[$i]}"
done

# ─── Quota Progress Bars ─────────────────────────────────────────────────────
quota_lines=()

if [ "$show_quota" = true ]; then
    MODEL_ID_LOWER=$(echo "$MODEL_ID" | tr '[:upper:]' '[:lower:]')
    if echo "$MODEL_ID_LOWER" | grep -qiE 'claude|anthropic|3p'; then
        Q_5H_REM="$Q_3P_5H_REM"
        Q_5H_RESET="$Q_3P_5H_RESET"
        Q_WK_REM="$Q_3P_WK_REM"
        Q_WK_RESET="$Q_3P_WK_RESET"
        pool_label="claude"
    else
        Q_5H_REM="$Q_GEM_5H_REM"
        Q_5H_RESET="$Q_GEM_5H_RESET"
        Q_WK_REM="$Q_GEM_WK_REM"
        Q_WK_RESET="$Q_GEM_WK_RESET"
        pool_label="gemini"
    fi

    # 5h Quota
    if line_5h=$(format_quota_line "${pool_label} 5h" "$Q_5H_REM" "$Q_5H_RESET" "time"); then
        quota_lines+=("$line_5h")
    fi

    # Weekly Quota
    if line_wk=$(format_quota_line "${pool_label} 7d" "$Q_WK_REM" "$Q_WK_RESET" "datetime"); then
        quota_lines+=("$line_wk")
    fi
fi

if [ -n "$PLAN_TIER" ] && [ "$PLAN_TIER" != "null" ]; then
    quota_lines=("${FG_GRAY}plan:${R} ${FG_WHITE}${PLAN_TIER}${R}" "${quota_lines[@]}")
fi

# ─── Render Layout Based on Terminal Width ───────────────────────────────────
if [ "$COLS" -ge "$CONFIG_LAYOUT_WIDE_COLS" ]; then
    # Wide layout
    echo -e "${LINE1}${FG_GRAY}  ${charPipe}  ${R}${CTX}"
    echo -e "${LINE_TELEMETRY}"
elif [ "$COLS" -ge "$CONFIG_LAYOUT_MED_COLS" ]; then
    # Medium layout
    echo -e "${FG_GRAY}╭─${R} ${LINE1}"
    echo -e "${FG_GRAY}╰─${R}${LINE2}"
else
    # Narrow layout: split into 4 structured lines
    parts_1a=()
    [ -n "$S" ] && parts_1a+=("$S")
    [ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "null" ] && parts_1a+=("${FG_BRIGHT_MAGENTA}${I}${MODEL_NAME}${R}")

    LINE1A=""
    for ((i = 0; i < ${#parts_1a[@]}; i++)); do
        if [ "$i" -gt 0 ]; then
            LINE1A+="${FG_GRAY} ${charSlash} ${R}"
        fi
        LINE1A+="${parts_1a[$i]}"
    done

    LINE1B="$DBlock"
    LINE2A=" ${CTX}"

    stats_only=()
    for ((i = 1; i < ${#stat_parts[@]}; i++)); do
        stats_only+=("${stat_parts[$i]}")
    done

    if [ "${#stats_only[@]}" -gt 0 ]; then
        LINE2B=" "
        for ((i = 0; i < ${#stats_only[@]}; i++)); do
            if [ "$i" -gt 0 ]; then
                LINE2B+="$DOT"
            fi
            LINE2B+="${stats_only[$i]}"
        done

        echo -e "${FG_GRAY}╭─${R} ${LINE1A}"
        echo -e "${FG_GRAY}├─${R} ${LINE1B}"
        echo -e "${FG_GRAY}├─${R}${LINE2A}"
        echo -e "${FG_GRAY}╰─${R}${LINE2B}"
    else
        echo -e "${FG_GRAY}╭─${R} ${LINE1A}"
        echo -e "${FG_GRAY}├─${R} ${LINE1B}"
        echo -e "${FG_GRAY}╰─${R}${LINE2A}"
    fi
fi

for qLine in "${quota_lines[@]}"; do
    echo -e "$qLine"
done

# Add a trailing empty line for padding at the bottom of the terminal
echo ""

exit 0
