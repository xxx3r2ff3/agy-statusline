#!/bin/bash
set -f

# ─── Ensure graceful failure ──────────────────────────────────────────────────
trap 'printf "agy (error at line %s)\n" "$LINENO"; exit 0' ERR

# ─── Read Stdin ─────────────────────────────────────────────────────────────
input=$(cat)
if [ -z "$input" ]; then
    printf "agy\n"
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
    {
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
    } | tr -d '\r'
)"

# ─── Configuration Constants ──────────────────────────────────────────────────
CONFIG_LAYOUT_WIDE_COLS=120
CONFIG_LAYOUT_MED_COLS=100
CONFIG_BAR_LEN_CTX=15
CONFIG_BAR_LEN_CTX_NARROW=8
charSlash="/"
charPipe="│"
charSigma="Σ"
CONFIG_BAR_LEN_QUOTA=10
CONFIG_CTX_WARN_PCT=60
CONFIG_CTX_CRIT_PCT=90
CONFIG_QUOTA_INFO_PCT=50
CONFIG_QUOTA_WARN_PCT=70
CONFIG_QUOTA_CRIT_PCT=90

if ! [[ "$COLS" =~ ^[0-9]+$ ]] || [ "$COLS" -lt 20 ]; then
    COLS=80
fi

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
        {
            jq -r '
          (if .show_quota == null then true else .show_quota end),
          (if .show_additional_stats == null then true else .show_additional_stats end),
          (if .hide_zero_stats == null then true else .hide_zero_stats end),
          (if .show_state_indicator == null then true else .show_state_indicator end)
        ' "$CONFIG_PATH" 2>/dev/null || printf "true\ntrue\ntrue\ntrue\n"
        } | tr -d '\r'
    )"
    [ "$cfg_quota" = "false" ] && show_quota=false
    [ "$cfg_stats" = "false" ] && show_additional_stats=false
    [ "$cfg_hide_zero" = "false" ] && hide_zero_stats=false
    [ "$cfg_state" = "false" ] && show_state_indicator=false
fi

# ─── ANSI Colors & Formatting (Standard 16 colors) ───────────────────────────
R="\033[0m"
B="\033[1m"
I="\033[3m"
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
        git_branch=$(git -C "$CWD" branch --show-current 2>/dev/null || true)
        if [ -n "$git_branch" ]; then
            VCS_BRANCH="$git_branch"
            git_status=$(git -C "$CWD" status --porcelain 2>/dev/null || true)
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
    local tilde="~"
    case "$p" in
        "$tilde") p="$HOME" ;;
        "$tilde/"*) p="$HOME/${p#"$tilde"/}" ;;
    esac
    if [ ! -f "$p" ]; then
        case "$p" in
            */antigravity/*)
                local alt="${p%%/antigravity/*}/antigravity-cli/${p#*/antigravity/}"
                [ -f "$alt" ] && p="$alt"
                ;;
        esac
    fi
    printf "%s" "$p"
}

parse_transcript_metrics() {
    local tpath="$1"
    if [ -z "$tpath" ] || [ ! -f "$tpath" ]; then
        printf "0 0 0 0 0\n"
        return
    fi

    local file_size
    file_size=$(wc -c <"$tpath" 2>/dev/null | tr -d '[:space:]' || echo 0)
    if ! [[ "$file_size" =~ ^[0-9]+$ ]] || [ "$file_size" -eq 0 ]; then
        printf "0 0 0 0 0\n"
        return
    fi

    local path_hash cache_dir cache_file
    path_hash=$(printf "%s" "$tpath" | cksum | awk '{print $1}')
    cache_dir="${TMPDIR:-/tmp}"
    cache_file="${cache_dir%/}/agy_sl_${path_hash}.cache"

    local c_offset=0 c_turns=0 c_planners=0 c_compacts=0 c_skip_drop=0 c_sigma=0
    local c_prev_ctx=0 c_prev_planner=0 c_prev_out=0 c_prev_ts=-1 c_samples=""

    if [ -f "$cache_file" ]; then
        local cached_path=""
        {
            IFS= read -r cached_path || true
            IFS= read -r c_offset c_turns c_planners c_compacts c_skip_drop c_sigma c_prev_ctx c_prev_planner c_prev_out c_prev_ts c_samples || true
        } <"$cache_file"
        if [ "$cached_path" != "$tpath" ] || ! [[ "${c_offset:-}" =~ ^[0-9]+$ ]] || [ "$file_size" -lt "$c_offset" ]; then
            c_offset=0
            c_turns=0
            c_planners=0
            c_compacts=0
            c_skip_drop=0
            c_sigma=0
            c_prev_ctx=0
            c_prev_planner=0
            c_prev_out=0
            c_prev_ts=-1
            c_samples=""
        fi
    fi

    if [ "$file_size" -gt "$c_offset" ]; then
        local ends_nl new_offset="$file_size" complete_bytes=0
        ends_nl=$(tail -c 1 "$tpath" 2>/dev/null | wc -l | tr -d '[:space:]' || echo 0)
        if [ "$ends_nl" -eq 1 ]; then
            complete_bytes=$((file_size - c_offset))
        else
            complete_bytes=$(tail -c +"$((c_offset + 1))" "$tpath" 2>/dev/null | sed '$d' | wc -c | tr -d '[:space:]' || echo 0)
            new_offset=$((c_offset + complete_bytes))
        fi

        if [ "$complete_bytes" -gt 0 ]; then
            local new_state
            new_state=$(
                tail -c +"$((c_offset + 1))" "$tpath" 2>/dev/null | head -c "$complete_bytes" | jq -Rr '
                            try fromjson catch empty |
                            select(type == "object") |
                            [
                                (.type // ""),
                                (.created_at // ""),
                                (.input_tokens // 0),
                                (.cache_read_tokens // 0),
                                (.cache_creation_tokens // 0),
                                (.output_tokens // 0)
                            ] | @tsv
                        ' 2>/dev/null | tr -d '\r' | LC_NUMERIC=C awk -F'\t' \
                    -v turns="$c_turns" \
                    -v planners="$c_planners" \
                    -v compacts="$c_compacts" \
                    -v skip_drop="$c_skip_drop" \
                    -v sigma="$c_sigma" \
                    -v prev_ctx="$c_prev_ctx" \
                    -v prev_planner="$c_prev_planner" \
                    -v prev_out="$c_prev_out" \
                    -v prev_ts="$c_prev_ts" \
                    -v samples="$c_samples" '
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
                            n_samp = 0
                            if (samples != "") {
                                n_samp = split(samples, samp_arr, ",")
                            }
                        }
                        {
                            stype = $1
                            if (stype == "") next
                            ts = ($2 != "") ? iso_to_epoch($2) : -1
                            if (prev_planner && stype == "GENERIC" && ts >= 0 && prev_ts >= 0) {
                                dt = ts - prev_ts
                                if (dt >= 1.0 && dt <= 120.0 && prev_out > 0) {
                                    n_samp++
                                    samp_arr[n_samp] = prev_out ":" dt
                                }
                            }
                            prev_planner = 0
                            if (stype == "USER_INPUT") {
                                turns++
                            } else if (stype == "CHECKPOINT" || stype == "COMPACT") {
                                compacts++
                                skip_drop = 1
                            } else if (stype == "PLANNER_RESPONSE") {
                                planners++
                                s_in = $3 + 0
                                s_cr = $4 + 0
                                s_cc = $5 + 0
                                s_out = $6 + 0
                                sigma += s_in + s_cr + s_cc + s_out
                                cur_ctx = s_in + s_cr
                                if (skip_drop == 0 && prev_ctx > 0 && (prev_ctx - cur_ctx) > 30000) {
                                    compacts++
                                }
                                skip_drop = 0
                                prev_ctx = cur_ctx
                                prev_planner = 1
                                prev_out = s_out
                                prev_ts = ts
                            }
                        }
                        END {
                            start_idx = (n_samp > 10) ? (n_samp - 9) : 1
                            out_samp = ""
                            for (i = start_idx; i <= n_samp; i++) {
                                if (samp_arr[i] != "") {
                                    out_samp = (out_samp == "") ? samp_arr[i] : out_samp "," samp_arr[i]
                                }
                            }
                            printf "%d %d %d %d %.0f %.0f %d %.0f %d %s\n", turns, planners, compacts, skip_drop, sigma, prev_ctx, prev_planner, prev_out, prev_ts, out_samp
                        }' || true
            )
            if [ -n "$new_state" ]; then
                read -r c_turns c_planners c_compacts c_skip_drop c_sigma c_prev_ctx c_prev_planner c_prev_out c_prev_ts c_samples <<<"$new_state"
                c_offset="$new_offset"
                {
                    printf "%s\n" "$tpath"
                    printf "%s %s %s %s %s %s %s %s %s %s %s\n" \
                        "$c_offset" "$c_turns" "$c_planners" "$c_compacts" "$c_skip_drop" "$c_sigma" \
                        "$c_prev_ctx" "$c_prev_planner" "$c_prev_out" "$c_prev_ts" "$c_samples"
                } >"${cache_file}.tmp" 2>/dev/null && mv -f "${cache_file}.tmp" "$cache_file" 2>/dev/null || true
            fi
        fi
    fi

    local display_turns="$c_turns"
    if [ "$display_turns" -eq 0 ] && [ "$c_planners" -gt 0 ]; then
        display_turns=1
    fi

    local avg_tps=0
    if [ -n "$c_samples" ]; then
        avg_tps=$(LC_NUMERIC=C awk -v s="$c_samples" 'BEGIN {
            n = split(s, arr, ",")
            sum_out = 0; sum_dt = 0
            for (i = 1; i <= n; i++) {
                if (split(arr[i], kv, ":") == 2) {
                    sum_out += kv[1] + 0
                    sum_dt += kv[2] + 0
                }
            }
            if (sum_dt > 0) printf "%.6f", sum_out / sum_dt
            else printf "0"
        }')
    fi

    printf "%d %d %.0f %s 1\n" "$display_turns" "$c_compacts" "$c_sigma" "$avg_tps"
}

truncate_ansi_line() {
    local line="$1"
    local max_cols="$2"
    local expanded
    expanded=$(printf "%b" "$line")
    LC_ALL=C awk -v maxw="$max_cols" '
    BEGIN {
        for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
    }
    function char_width(cp) {
        if (cp >= 65024 && cp <= 65039) return 0
        if (cp == 8205) return 0
        if (cp == 8986 || cp == 8987) return 2
        if ((cp >= 11904 && cp <= 40959) || (cp >= 63744 && cp <= 64255) || (cp >= 65072 && cp <= 65135) || (cp >= 65280 && cp <= 65519)) return 2
        return 1
    }
    {
        s = $0
        n = length(s)
        i = 1
        vis = 0
        out = ""
        last_fit_out = ""
        truncated = 0

        while (i <= n) {
            c = substr(s, i, 1)
            b = ord[c]

            if (b == 27 && i < n && substr(s, i + 1, 1) == "[") {
                j = i + 2
                while (j <= n) {
                    jc = substr(s, j, 1)
                    if (jc ~ /[A-Za-z]/) break
                    j++
                }
                seq = substr(s, i, j - i + 1)
                out = out seq
                if (vis <= maxw - 1) last_fit_out = last_fit_out seq
                i = j + 1
                continue
            }

            if (b < 128) {
                tok = c
                cw = (b >= 32) ? 1 : 0
                step = 1
            } else if (b >= 194 && b <= 223 && i + 1 <= n) {
                b2 = ord[substr(s, i + 1, 1)]
                cp = (b - 192) * 64 + (b2 - 128)
                tok = substr(s, i, 2)
                cw = char_width(cp)
                step = 2
            } else if (b >= 224 && b <= 239 && i + 2 <= n) {
                b2 = ord[substr(s, i + 1, 1)]
                b3 = ord[substr(s, i + 2, 1)]
                cp = (b - 224) * 4096 + (b2 - 128) * 64 + (b3 - 128)
                tok = substr(s, i, 3)
                cw = char_width(cp)
                step = 3
            } else if (b >= 240 && b <= 247 && i + 3 <= n) {
                tok = substr(s, i, 4)
                cw = 2
                step = 4
            } else {
                tok = c
                cw = 1
                step = 1
            }

            if (vis + cw > maxw) {
                truncated = 1
                break
            }
            if (vis + cw <= maxw - 1) {
                last_fit_out = last_fit_out tok
            }
            out = out tok
            vis += cw
            i += step
        }

        if (truncated) {
            if (maxw >= 1) printf "%s…\033[0m\n", last_fit_out
            else printf "\033[0m\n"
        } else {
            printf "%s\n", out
        }
    }' <<<"$expanded"
}

emit_line() {
    truncate_ansi_line "$1" "$COLS"
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
    local style=$2
    [ -z "$reset_iso" ] || [ "$reset_iso" = "null" ] && return

    local epoch=""
    if date -d "$reset_iso" +%s >/dev/null 2>&1; then
        epoch=$(date -d "$reset_iso" +%s 2>/dev/null || true)
    elif date -j -f "%Y-%m-%dT%H:%M:%SZ" "$reset_iso" +%s >/dev/null 2>&1; then
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$reset_iso" +%s 2>/dev/null || true)
    elif date -j -f "%Y-%m-%dT%H:%M:%S%z" "$reset_iso" +%s >/dev/null 2>&1; then
        local clean_iso
        clean_iso="${reset_iso%:*}${reset_iso##*:}"
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$clean_iso" +%s 2>/dev/null || true)
    fi

    [ -z "$epoch" ] && return

    local result=""
    if date --version >/dev/null 2>&1; then
        if [ "$style" = "time" ]; then
            result=$(date -d "@$epoch" +"%H:%M" 2>/dev/null || true)
        else
            result=$(date -d "@$epoch" +"%b %-d, %H:%M" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
        fi
    else
        if [ "$style" = "time" ]; then
            result=$(date -r "$epoch" +"%H:%M" 2>/dev/null || true)
        else
            result=$(date -r "$epoch" +"%b %e, %H:%M" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/  */ /g' || true)
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
        -v tot_in="$TOTAL_IN_TOK" \
        -v cur_in="$CUR_IN_TOK" -v cur_cc="$CUR_CACHE_CREATE" -v cur_cr="$CUR_CACHE_READ" '
    BEGIN {
        prompt_tok = cur_in + cur_cc + cur_cr
        if (max_tok > 0 && used_pct > 0) {
            ctx_used = max_tok * used_pct / 100.0
        } else if (prompt_tok > 0) {
            ctx_used = prompt_tok
        } else {
            ctx_used = tot_in
        }
        cache_pct = (prompt_tok > 0) ? (cur_cr * 100.0 / prompt_tok) : 0
        printf "%.0f %.0f %.6f\n", ctx_used, prompt_tok, cache_pct
    }'
)"

NORM_TRANSCRIPT_PATH=$(normalize_transcript_path "$TRANSCRIPT_PATH")
read -r TURNS_COUNT COMPACT_COUNT SIGMA_TOKENS AVG_TOK_PER_SEC HAS_TRANSCRIPT <<<"$(parse_transcript_metrics "$NORM_TRANSCRIPT_PATH")"

bar_len="$CONFIG_BAR_LEN_CTX"
if [ "$COLS" -lt "$CONFIG_LAYOUT_WIDE_COLS" ]; then
    bar_len="$CONFIG_BAR_LEN_CTX_NARROW"
fi

PCT_INT=$(LC_NUMERIC=C printf "%.0f" "$USED_PCT" 2>/dev/null || echo 0)
FILLED=$(((PCT_INT * bar_len) / 100))
REMAINDER=$(((PCT_INT * bar_len) % 100))

if [ "$PCT_INT" -ge "$CONFIG_CTX_CRIT_PCT" ]; then
    BAR_COLOR="$FG_BRIGHT_RED"
elif [ "$PCT_INT" -ge "$CONFIG_CTX_WARN_PCT" ]; then
    BAR_COLOR="$FG_BRIGHT_YELLOW"
else
    BAR_COLOR="$FG_BRIGHT_WHITE"
fi

BAR=""
for ((i = 0; i < bar_len; i++)); do
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
if [ "$HAS_TRANSCRIPT" -eq 1 ]; then
    telemetry_parts+=("${FG_GRAY}Turns: ${NUM_COLOR}${TURNS_COUNT} ${FG_GRAY}(Compact: ${NUM_COLOR}${COMPACT_COUNT}${FG_GRAY})${R}")
fi
if LC_NUMERIC=C awk -v d="$CACHE_DENOM" 'BEGIN { exit !(d > 0) }'; then
    CACHE_PCT_FMT=$(LC_NUMERIC=C printf "%.1f" "$CACHE_PCT" 2>/dev/null || echo "0.0")
    CACHE_READ_FMT=$(format_tok "$CUR_CACHE_READ")
    telemetry_parts+=("${FG_GRAY}Cache: ${NUM_COLOR}${CACHE_PCT_FMT}% ${FG_GRAY}(${NUM_COLOR}${CACHE_READ_FMT}${FG_GRAY})${R}")
fi
if [ "$HAS_TRANSCRIPT" -eq 1 ] && LC_NUMERIC=C awk -v s="$SIGMA_TOKENS" 'BEGIN { exit !(s > 0) }'; then
    SIGMA_FMT=$(format_tok "$SIGMA_TOKENS")
    telemetry_parts+=("${FG_GRAY}${charSigma}Tok: ${NUM_COLOR}${SIGMA_FMT}${R}")
fi
if [ "$HAS_TRANSCRIPT" -eq 1 ] && LC_NUMERIC=C awk -v a="$AVG_TOK_PER_SEC" 'BEGIN { exit !(a > 0) }'; then
    AVG_FMT=$(LC_NUMERIC=C printf "%.0f" "$AVG_TOK_PER_SEC" 2>/dev/null || echo "0")
    telemetry_parts+=("${FG_GRAY}Avg: ${NUM_COLOR}~${AVG_FMT} tok/s${R}")
fi

extra_parts=()
if [ "$show_additional_stats" = true ]; then
    if [ "$hide_zero_stats" = false ] || [ "$ARTIFACTS" -gt 0 ]; then
        extra_parts+=("${FG_GRAY}artifacts ${NUM_COLOR}${ARTIFACTS}${R}")
    fi
    if [ "$hide_zero_stats" = false ] || [ "$SUBAGENTS" -gt 0 ]; then
        extra_parts+=("${FG_GRAY}subagents ${NUM_COLOR}${SUBAGENTS}${R}")
    fi
    if [ "$hide_zero_stats" = false ] || [ "$BG_TASKS" -gt 0 ]; then
        extra_parts+=("${FG_GRAY}tasks ${NUM_COLOR}${BG_TASKS}${R}")
    fi
    if [ "$SANDBOX" = "true" ]; then
        extra_parts+=("${FG_GRAY}sandbox ${FG_BRIGHT_GREEN}${B}ON${R}")
    elif [ "$hide_zero_stats" = false ]; then
        extra_parts+=("${FG_GRAY}sandbox off${R}")
    fi
fi

all_telemetry=("${telemetry_parts[@]}" "${extra_parts[@]}")

join_with() {
    local sep="$1"
    shift
    local out="" item
    for item in "$@"; do
        if [ -n "$out" ]; then
            out+="$sep"
        fi
        out+="$item"
    done
    printf "%s" "$out"
}

PIPE_SEP="${FG_GRAY} ${charPipe} ${R}"
DOT="${FG_GRAY} · ${R}"

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

    if line_5h=$(format_quota_line "${pool_label} 5h" "$Q_5H_REM" "$Q_5H_RESET" "time"); then
        quota_lines+=("$line_5h")
    fi

    if line_wk=$(format_quota_line "${pool_label} 7d" "$Q_WK_REM" "$Q_WK_RESET" "datetime"); then
        quota_lines+=("$line_wk")
    fi
fi

if [ -n "$PLAN_TIER" ] && [ "$PLAN_TIER" != "null" ]; then
    quota_lines=("${FG_GRAY}plan:${R} ${FG_WHITE}${PLAN_TIER}${R}" "${quota_lines[@]}")
fi

# ─── Render Layout Based on Terminal Width ───────────────────────────────────
if [ "$COLS" -ge "$CONFIG_LAYOUT_WIDE_COLS" ]; then
    emit_line "${LINE1}${FG_GRAY}  ${charPipe}  ${R}${CTX}"
    if [ "${#all_telemetry[@]}" -gt 0 ]; then
        emit_line "$(join_with "$PIPE_SEP" "${all_telemetry[@]}")"
    fi
elif [ "$COLS" -ge "$CONFIG_LAYOUT_MED_COLS" ]; then
    emit_line "${FG_GRAY}╭─${R} ${LINE1}"
    if [ "${#all_telemetry[@]}" -gt 0 ]; then
        emit_line "${FG_GRAY}├─${R} ${CTX}"
        emit_line "${FG_GRAY}╰─${R} $(join_with "$DOT" "${all_telemetry[@]}")"
    else
        emit_line "${FG_GRAY}╰─${R} ${CTX}"
    fi
else
    parts_1a=()
    [ -n "$S" ] && parts_1a+=("$S")
    [ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "null" ] && parts_1a+=("${FG_BRIGHT_MAGENTA}${I}${MODEL_NAME}${R}")
    LINE1A=$(join_with "${FG_GRAY} ${charSlash} ${R}" "${parts_1a[@]}")

    emit_line "${FG_GRAY}╭─${R} ${LINE1A}"
    emit_line "${FG_GRAY}├─${R} ${DBlock}"

    if [ "${#telemetry_parts[@]}" -gt 0 ] && [ "${#extra_parts[@]}" -gt 0 ]; then
        emit_line "${FG_GRAY}├─${R} ${CTX}"
        emit_line "${FG_GRAY}├─${R} $(join_with "$DOT" "${telemetry_parts[@]}")"
        emit_line "${FG_GRAY}╰─${R} $(join_with "$DOT" "${extra_parts[@]}")"
    elif [ "${#all_telemetry[@]}" -gt 0 ]; then
        emit_line "${FG_GRAY}├─${R} ${CTX}"
        emit_line "${FG_GRAY}╰─${R} $(join_with "$DOT" "${all_telemetry[@]}")"
    else
        emit_line "${FG_GRAY}╰─${R} ${CTX}"
    fi
fi

for qLine in "${quota_lines[@]}"; do
    emit_line "$qLine"
done

exit 0
