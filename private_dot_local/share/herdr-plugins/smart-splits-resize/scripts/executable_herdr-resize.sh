#!/usr/bin/env bash
#
# smart-splits.nvim resizing — herdr side
#
# Invoked by a herdr keybind as: herdr-resize.sh <left|down|up|right>
# Companion to the navigation script smart-splits.nvim ships (scripts/herdr-navigate.sh).
#
# Decision table per keypress:
#   1. Focused pane's foreground process matches Vim (or SMART_SPLITS_HERDR_PASSTHROUGH_RE):
#      forward the key into the pane; smart-splits resizes the Vim split and calls back into
#      herdr when Vim is at an edge.
#   2. Otherwise resize the herdr pane directly; if that changes nothing, send the key back to
#      the pane so the running app keeps its own Alt binding.
#
# `herdr pane resize --amount` takes a split-ratio delta, not cells, so the ratio is derived
# from the tab area to move the border a fixed number of cells like tmux's `resize-pane 3`.
#
# Requires `jq`. Without it, Vim detection is skipped and every keypress resizes the herdr pane.

set -euo pipefail

dir="${1:?usage: herdr-resize.sh <left|down|up|right>}"
herdr="${HERDR_BIN_PATH:-herdr}"
pane="${HERDR_PANE_ID:-}"
cells="${SMART_SPLITS_HERDR_RESIZE_CELLS:-3}"

case "$dir" in
  left)  key="alt+h" ;;
  down)  key="alt+j" ;;
  up)    key="alt+k" ;;
  right) key="alt+l" ;;
  *) echo "herdr-resize.sh: unknown direction: $dir" >&2; exit 2 ;;
esac

# Foreground process names that mean "Vim is in control of this pane".
vim_re='^g?(view|l?n?vim?x?)(diff)?$'

# Opt-in passthrough for other TUIs that own Alt+h/j/k/l themselves.
passthrough_re="${SMART_SPLITS_HERDR_PASSTHROUGH_RE:-}"

forward=0
if [ -n "$pane" ] && command -v jq >/dev/null 2>&1; then
  if "$herdr" pane process-info --current 2>/dev/null \
    | jq -e --arg vim "$vim_re" --arg pass "$passthrough_re" \
        '.result.process_info.foreground_processes[]?.name
         | ascii_downcase
         | select(test($vim) or ($pass != "" and (try test($pass) catch false)))' >/dev/null 2>&1; then
    forward=1
  fi
fi

if [ "$forward" -eq 1 ]; then
  exec "$herdr" pane send-keys "$pane" "$key"
fi

# Non-Vim pane: resize the herdr pane, or let the key through when nothing moved.
case "$dir" in
  left|right) axis="width" ;;
  up|down)    axis="height" ;;
esac

amount=""
if command -v jq >/dev/null 2>&1; then
  area="$("$herdr" pane layout --current 2>/dev/null | jq -r ".result.layout.area.$axis // empty" 2>/dev/null)"
  if [ -n "$area" ] && [ "$area" -gt 0 ] 2>/dev/null; then
    amount="$(awk -v c="$cells" -v a="$area" 'BEGIN { printf "%.4f", c / a }')"
  fi
fi
[ -n "$amount" ] || amount="0.02"

resize_output="$("$herdr" pane resize --direction "$dir" --amount "$amount" --current 2>/dev/null)" && exit_code=0 || exit_code=$?
if [ "$exit_code" -eq 0 ] && [ -n "$resize_output" ] && command -v jq >/dev/null 2>&1; then
  changed="$(printf '%s' "$resize_output" | jq -r '.result.resize.changed // false' 2>/dev/null)"
  if [ "$changed" = "true" ]; then
    exit 0
  fi
fi
exec "$herdr" pane send-keys "$pane" "$key"
