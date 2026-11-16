#!/usr/bin/env bash

## Author : Aditya Shakya (adi1090x)
## Github : @adi1090x
#
## Rofi   : Power Menu

# Current Theme
dir="$HOME/.config/rofi/themes"
theme='powermenu'

# CMDs
uptime="$(uptime -p | sed -e 's/up //g')"
host=$(hostname)

# Record a work-hours lock/unlock event, but only where the tool is installed
# (the Hyprland host). hyprlock/swaylock/betterlockscreen all block in the
# foreground until unlock, so the unlock event fires right after the locker exits.
wh_event() { command -v work-hours >/dev/null 2>&1 && work-hours event "$1"; }

# Options
shutdown=' Shutdown'
reboot=' Reboot'
lock=' Lock'
suspend='鈴 Suspend'
logout=' Logout'
yes=' Yes'
no=' No'

# Rofi CMD
rofi_cmd() {
  rofi -dmenu \
    -p "$host" \
    -mesg "Uptime: $uptime" \
    -theme "${dir}/${theme}.rasi"
}

# Confirmation CMD
confirm_cmd() {
  rofi -theme-str 'window {location: center; anchor: center; fullscreen: false; width: 250px;}' \
    -theme-str 'mainbox {children: [ "message", "listview" ];}' \
    -theme-str 'listview {columns: 2; lines: 1;}' \
    -theme-str 'element-text {horizontal-align: 0.5;}' \
    -theme-str 'textbox {horizontal-align: 0.5;}' \
    -dmenu \
    -p 'Confirmation' \
    -mesg 'Are you Sure?' \
    -theme "${dir}/${theme}.rasi"
}

# Ask for confirmation
confirm_exit() {
  echo -e "$yes\n$no" | confirm_cmd
}

# Pass variables to rofi dmenu
run_rofi() {
  echo -e "$lock\n$suspend\n$logout\n$reboot\n$shutdown" | rofi_cmd
}

# Execute Command
run_cmd() {
  selected="$(confirm_exit)"
  if [[ "$selected" == "$yes" ]]; then
    if [[ $1 == '--shutdown' ]]; then
      systemctl poweroff
    elif [[ $1 == '--reboot' ]]; then
      systemctl reboot
    elif [[ $1 == '--suspend' ]]; then
      mpc -q pause
      amixer set Master mute
      systemctl suspend
    elif [[ $1 == '--logout' ]]; then
      if [[ "$XDG_CURRENT_DESKTOP" == 'Hyprland' ]]; then
        hyprctl dispatch exit
      elif [[ "$XDG_CURRENT_DESKTOP" == 'openbox' ]]; then
        openbox --exit
      elif [[ "$XDG_CURRENT_DESKTOP" == 'bspwm' ]]; then
        bspc quit
      elif [[ "$XDG_CURRENT_DESKTOP" == 'i3' ]]; then
        i3-msg exit
      elif [[ "$XDG_CURRENT_DESKTOP" == 'plasma' ]]; then
        qdbus org.kde.ksmserver /KSMServer logout 0 0 0
      else
        i3-msg exit
      fi
    fi
  else
    exit 0
  fi
}

# Actions
chosen="$(run_rofi)"
case ${chosen} in
"$shutdown")
  run_cmd --shutdown
  ;;
"$reboot")
  run_cmd --reboot
  ;;
"$lock")
  playerctl --all-players stop
  if [[ -x '/usr/bin/hyprlock' ]]; then
    if ! pidof hyprlock >/dev/null; then
      #wh_event lock
      loginctl lock-session
      #wh_event unlock
    fi
  elif [[ -x '/usr/bin/swaylock' ]]; then
    wh_event lock
    swaylock --image ~/Pictures/wallpapers/planet.png
    wh_event unlock
  elif [[ -x '/usr/bin/betterlockscreen' ]]; then
    wh_event lock
    betterlockscreen -l dimblur
    wh_event unlock
  fi
  ;;
"$suspend")
  run_cmd --suspend
  ;;
"$logout")
  run_cmd --logout
  ;;
esac
