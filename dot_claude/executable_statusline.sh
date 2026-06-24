#!/usr/bin/env bash
# Claude Code status line.
# Reads the status JSON on stdin and prints a single line:
#   [user@host dir]  ⎇ branch  PR #123 ✓  ◔ 25k/200k  5h 23% · 7d 41%
# All data comes from the status JSON (see `claude` docs); no extra `gh` call
# is needed — Claude Code injects the PR + rate-limit info itself.

input=$(cat)

# Pull everything we need in a single jq pass.
# NOTE: fields are joined with the ASCII unit separator (), NOT a tab.
# Tab is an IFS *whitespace* char, so `read` would collapse consecutive empty
# fields and shift values into the wrong variables.
IFS=$'\x1f' read -r cwd used_pct ctx_used ctx_size pr_num review five seven < <(
  printf '%s' "$input" | jq -r '
    [ .cwd // "",
      (.context_window.used_percentage // ""),
      ((.context_window.current_usage // {})
        | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
        | if . == 0 then "" else . end),
      (.context_window.context_window_size // ""),
      (.pr.number // ""),
      (.pr.review_state // ""),
      (.rate_limits.five_hour.used_percentage // ""),
      (.rate_limits.seven_day.used_percentage // "")
    ] | map(tostring) | join("")'
)

# Colours.
RESET=$'\e[0m'
DIM=$'\e[2m'
BOLD=$'\e[1m'
GREY=$'\e[90m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
RED=$'\e[31m'
BLUE=$'\e[34m'
MAGENTA=$'\e[35m'
CYAN=$'\e[36m'

# round "23.5" -> "24"; empty stays empty
round() { [ -n "$1" ] && printf '%.0f' "$1"; }

# 249389 -> 249k, 1000000 -> 1.0M, 512 -> 512
human() {
  local n=$1
  [ -z "$n" ] && return
  if [ "$n" -ge 1000000 ]; then
    awk "BEGIN{printf \"%.1fM\", $n/1000000}"
  elif [ "$n" -ge 1000 ]; then
    awk "BEGIN{printf \"%dk\",  $n/1000}"
  else printf '%d' "$n"; fi
}

# colour a percentage green/yellow/red by thresholds (warn, crit)
pct_colour() {
  local v=${1:-0} warn=$2 crit=$3
  if [ "$v" -ge "$crit" ]; then
    printf '%s' "$RED"
  elif [ "$v" -ge "$warn" ]; then
    printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

# --- segment: [user@host dir] -------------------------------------------------
dir=$(basename "${cwd:-$PWD}")
out="${GREY}[${RESET}${BOLD}$(whoami)${RESET}${GREY}@${RESET}$(hostname -s) ${CYAN}${dir}${RESET}${GREY}]${RESET}"

# --- segment: git branch ------------------------------------------------------
branch=$(git -C "${cwd:-$PWD}" branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
  dirty=""
  [ -n "$(git -C "${cwd:-$PWD}" status --porcelain 2>/dev/null)" ] && dirty="${YELLOW}*${RESET}"
  out+="  ${MAGENTA}⎇ ${branch}${RESET}${dirty}"
fi

# --- segment: PR --------------------------------------------------------------
if [ -n "$pr_num" ]; then
  case "$review" in
  approved) mark="${GREEN}✓${RESET}" ;;
  changes_requested) mark="${RED}✗${RESET}" ;;
  pending) mark="${YELLOW}…${RESET}" ;;
  *) mark="" ;;
  esac
  out+="  ${BLUE}PR #${pr_num}${RESET}${mark:+ $mark}"
fi

# --- segment: context window (used / total tokens) ---------------------------
if [ -n "$ctx_used" ] && [ -n "$ctx_size" ]; then
  c=$(pct_colour "$(round "$used_pct")" 60 85)
  out+="  ${c}◔ $(human "$ctx_used")/$(human "$ctx_size")${RESET}"
fi

# --- segment: usage limits (Pro/Max only, after first API response) ----------
five=$(round "$five")
seven=$(round "$seven")
if [ -n "$five" ] || [ -n "$seven" ]; then
  lim=""
  [ -n "$five" ] && lim+="$(pct_colour "$five" 70 90)5h ${five}%${RESET}"
  [ -n "$five" ] && [ -n "$seven" ] && lim+="${DIM} · ${RESET}"
  [ -n "$seven" ] && lim+="$(pct_colour "$seven" 70 90)7d ${seven}%${RESET}"
  out+="  ${lim}"
fi

printf '%s' "$out"
