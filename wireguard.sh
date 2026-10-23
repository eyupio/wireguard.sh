#!/bin/bash
# wireguard.sh — a guided WireGuard installer.
# Developed by EyUp.io (https://eyup.io). Licensed GPL-3.0.
#
# This installer builds on the excellent wireguard-install project by Nyr:
# https://github.com/Nyr/wireguard-install
# WireGuard itself is the work of Jason A. Donenfeld and the WireGuard project:
# https://www.wireguard.com/
# We take no credit for their work, and this project is not affiliated with or
# endorsed by the WireGuard project or Nyr.

APP_NAME="wireguard.sh"
APP_VERSION="1.2"
APP_AUTHOR="EyUp.io"
APP_AUTHOR_URL="https://eyup.io"
APP_REPO_URL="https://github.com/eyupio/wireguard.sh"
UPSTREAM_URL="https://github.com/Nyr/wireguard-install"
WIREGUARD_URL="https://www.wireguard.com/"

TUI_COLOR_MODE="${TUI_COLOR:-auto}"
TUI_ASCII_MODE="${TUI_ASCII:-0}"
TUI_PREVIEW=0
TUI_DRY_RUN=0
TUI_VERBOSE=0
TUI_NO_CLEAR=0
TUI_TTY=0
TUI_INPUT_READY=0
TUI_CAN_KEY=0
TUI_CLEANED=0
TUI_CHILD_PID=""
TUI_WIDTH=78
TUI_INNER=72
TUI_MENU_LINES=0
TUI_MENU_RESULT=0
TUI_MENU_DEFAULT=0
TUI_LINE=""
TUI_KEY=""
TUI_INPUT_RESULT=""
LOGFILE="/var/log/wireguardSH.log"

os=""
os_version=""
os_pretty=""
os_label=""
is_container=1
virtualization=""
ip=""
ip6=""
public_ip=""
port=""
client=""
dns=""
dns_label=""
boringtun_updates="y"
cron=""
firewall=""
architecture=""

show_help=0
show_version=0

print_help() {
  cat <<EOF
${APP_NAME} ${APP_VERSION} — a guided WireGuard installer

Usage:
  bash ${APP_NAME} [options]

Options:
  -h, --help       Show this help and exit.
  -V, --version    Show the version and exit.
      --preview    Render the TUI screens without changing the system.
      --dry-run    Walk the wizard without installing anything.
      --no-color   Disable colour output.
      --ascii      Use ASCII box drawing for limited terminals.
      --verbose    Show command output while installing.

The installer needs bash, root privileges, systemd, and a supported
Ubuntu, Debian, CentOS, or Fedora release.

Credits:
  WireGuard was created by Jason A. Donenfeld and the WireGuard project.
  ${WIREGUARD_URL}
  The install flow builds on Nyr's wireguard-install.
  ${UPSTREAM_URL}
  ${APP_NAME} is independent and is not endorsed by either project.
  Developed by ${APP_AUTHOR}: ${APP_AUTHOR_URL}

Source: ${APP_REPO_URL}
EOF
}

tui_use_color() {
  [[ "$TUI_COLOR_MODE" == "always" ]] && return 0
  [[ "$TUI_COLOR_MODE" == "never" ]] && return 1
  [[ -n "${NO_COLOR:-}" ]] && return 1
  [[ "$TUI_TTY" -eq 1 ]]
}

tui_use_unicode() {
  [[ "$TUI_ASCII_MODE" == "1" ]] && return 1
  [[ "${TERM:-}" == "dumb" ]] && return 1
  local charmap
  charmap="$(locale charmap 2>/dev/null || true)"
  [[ -z "$charmap" || "$charmap" == "UTF-8" ]]
}

tui_set_theme() {
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_CYAN=""
  C_WHITE=""

  if tui_use_color; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[1;31m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_CYAN=$'\033[1;36m'
    C_WHITE=$'\033[1;37m'
  fi

  if tui_use_unicode; then
    TUI_TL="┌"
    TUI_TR="┐"
    TUI_BL="└"
    TUI_BR="┘"
    TUI_H="─"
    TUI_V="│"
    TUI_LT="├"
    TUI_RT="┤"
    TUI_CURSOR="❯"
    TUI_CHECK="✓"
    TUI_CROSS="✗"
    TUI_WARN="!"
    TUI_DOT="●"
    TUI_BULLET="•"
    TUI_UP="↑"
    TUI_DOWN="↓"
    TUI_SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  else
    TUI_TL="+"
    TUI_TR="+"
    TUI_BL="+"
    TUI_BR="+"
    TUI_H="-"
    TUI_V="|"
    TUI_LT="+"
    TUI_RT="+"
    TUI_CURSOR=">"
    TUI_CHECK="OK"
    TUI_CROSS="X"
    TUI_WARN="!"
    TUI_DOT="*"
    TUI_BULLET="*"
    TUI_UP="^"
    TUI_DOWN="v"
    TUI_SPINNER=("-" "\\" "|" "/")
  fi
}

tui_repeat() {
  local char="$1" count="$2" out=""
  while (( count-- > 0 )); do
    out+="$char"
  done
  printf '%s' "$out"
}

tui_measure() {
  local cols="${COLUMNS:-}"
  if [[ -z "$cols" && "$TUI_TTY" -eq 1 ]] && command -v tput >/dev/null 2>&1; then
    cols="$(tput cols 2>/dev/null || true)"
  fi
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  (( cols > 82 )) && cols=82
  (( cols < 40 )) && cols=40
  TUI_WIDTH=$(( cols - 2 ))
  (( TUI_WIDTH > 78 )) && TUI_WIDTH=78
  (( TUI_WIDTH < 36 )) && TUI_WIDTH=36
  TUI_INNER=$(( TUI_WIDTH - 4 ))
}

tui_clear() {
  if [[ "$TUI_TTY" -eq 1 && "$TUI_NO_CLEAR" -ne 1 && "${TERM:-}" != "dumb" ]]; then
    printf '\033[H\033[2J'
  fi
}

tui_cleanup() {
  [[ "$TUI_CLEANED" -eq 1 ]] && return
  TUI_CLEANED=1
  if [[ -n "$TUI_CHILD_PID" ]]; then
    kill "$TUI_CHILD_PID" 2>/dev/null || true
  fi
  if [[ "$TUI_TTY" -eq 1 && "${TERM:-}" != "dumb" ]]; then
    printf '\033[?25h%s' "$C_RESET"
  else
    printf '%s' "$C_RESET"
  fi
}

tui_init() {
  TUI_TTY=0
  [[ -t 1 ]] && TUI_TTY=1

  TUI_INPUT_READY=0
  if [[ -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then
    TUI_INPUT_READY=1
  fi

  TUI_CAN_KEY=0
  if [[ "$TUI_INPUT_READY" -eq 1 && "$TUI_TTY" -eq 1 && "${TERM:-}" != "dumb" ]]; then
    TUI_CAN_KEY=1
  fi
  if [[ "$TUI_PREVIEW" -eq 1 ]]; then
    TUI_CAN_KEY=0
  fi

  tui_set_theme
  tui_measure

  if [[ "$TUI_TTY" -eq 1 && "${TERM:-}" != "dumb" ]]; then
    printf '\033[?25l'
  fi
  trap 'tui_cleanup' EXIT
  trap 'tui_cleanup; exit 130' INT TERM
}

tui_box_top() {
  printf '  %s%s%s%s%s\n' "$C_DIM" "$TUI_TL" "$(tui_repeat "$TUI_H" $((TUI_WIDTH - 2)))" "$TUI_TR" "$C_RESET"
}

tui_box_sep() {
  printf '  %s%s%s%s%s\n' "$C_DIM" "$TUI_LT" "$(tui_repeat "$TUI_H" $((TUI_WIDTH - 2)))" "$TUI_RT" "$C_RESET"
}

tui_box_bottom() {
  printf '  %s%s%s%s%s\n' "$C_DIM" "$TUI_BL" "$(tui_repeat "$TUI_H" $((TUI_WIDTH - 2)))" "$TUI_BR" "$C_RESET"
}

tui_fit() {
  local text="$1"
  if (( ${#text} > TUI_INNER )); then
    if [[ "$TUI_ASCII_MODE" == "1" ]]; then
      printf '%s' "${text:0:$((TUI_INNER - 3))}..."
    else
      printf '%s' "${text:0:$((TUI_INNER - 1))}…"
    fi
  else
    printf '%s' "$text"
  fi
}

tui_box_row() {
  local text color pad
  text="$(tui_fit "$1")"
  color="${2:-}"
  pad=$((TUI_INNER - ${#text}))
  (( pad < 0 )) && pad=0
  printf '  %s%s%s %s%s%s%*s %s%s%s\n' \
    "$C_DIM" "$TUI_V" "$C_RESET" \
    "$color" "$text" "$C_RESET" \
    "$pad" "" \
    "$C_DIM" "$TUI_V" "$C_RESET"
}

tui_box_pair() {
  local left="$1" right="$2" color="${3:-}" gap
  gap=$((TUI_INNER - ${#left} - ${#right}))
  if (( gap < 1 )); then
    left="${left:0:$((TUI_INNER - ${#right} - 1))}"
    gap=1
  fi
  tui_box_row "${left}$(printf '%*s' "$gap" '')${right}" "$color"
}

tui_box_kv() {
  local label="$1" value="$2" line
  printf -v line '  %-16s %s' "$label" "$value"
  tui_box_row "$line"
}

tui_box_blank() {
  tui_box_row ""
}

tui_section() {
  printf '\n  %s%s%s\n' "$C_BOLD$C_WHITE" "$1" "$C_RESET"
  printf '  %s%s%s\n' "$C_DIM" "$(tui_repeat "$TUI_H" $((TUI_WIDTH - 2)))" "$C_RESET"
}

tui_paragraph() {
  local text="$1" width=$((TUI_WIDTH - 8)) line
  while IFS= read -r line; do
    printf '  %s\n' "$line"
  done < <(printf '%s\n' "$text" | fold -s -w "$width" | sed 's/[[:space:]]*$//')
}

tui_note() {
  local color="$1" icon="$2" text="$3" width=$((TUI_WIDTH - 10))
  local line first=1 pad
  printf -v pad '%*s' $(( ${#icon} + 1 )) ''
  while IFS= read -r line; do
    if (( first == 1 )); then
      printf '  %s%s%s %s\n' "$color" "$icon" "$C_RESET" "$line"
      first=0
    else
      printf '  %s%s%s%s\n' "$color" "$pad" "$line" "$C_RESET"
    fi
  done < <(printf '%s\n' "$text" | fold -s -w "$width" | sed 's/[[:space:]]*$//')
}

tui_success() {
  tui_note "$C_GREEN" "$TUI_CHECK" "$1"
}

tui_warn() {
  tui_note "$C_YELLOW" "$TUI_WARN" "$1"
}

tui_error() {
  tui_note "$C_RED" "$TUI_CROSS" "$1"
}

tui_die() {
  local message="$1" hint="${2:-}"
  printf '\n'
  tui_error "$message"
  if [[ -n "$hint" ]]; then
    tui_paragraph "$hint"
  fi
  printf '\n'
  tui_cleanup
  exit 1
}

tui_read_line() {
  TUI_LINE=""
  if [[ "$TUI_INPUT_READY" -eq 1 ]]; then
    IFS= read -r TUI_LINE < /dev/tty
  else
    IFS= read -r TUI_LINE
  fi
}

tui_getkey() {
  local key rest
  TUI_KEY=""
  if [[ "$TUI_INPUT_READY" -eq 1 ]]; then
    IFS= read -rsn1 key < /dev/tty || return 1
  else
    IFS= read -rsn1 key || return 1
  fi
  if [[ "$key" == $'\e' ]]; then
    if [[ "$TUI_INPUT_READY" -eq 1 ]]; then
      IFS= read -rsn2 -t 0.05 rest < /dev/tty || true
    else
      IFS= read -rsn2 -t 0.05 rest || true
    fi
    key+="$rest"
  fi
  TUI_KEY="$key"
}

tui_brand_header() {
  tui_box_top
  tui_box_pair "  ${APP_NAME}" "v${APP_VERSION}  " "$C_CYAN$C_BOLD"
  tui_box_pair "  Guided WireGuard installer" "by ${APP_AUTHOR}  " "$C_DIM"
  tui_box_bottom
}

tui_screen_start() {
  local title="$1" subtitle="${2:-}"
  tui_clear
  tui_measure
  tui_brand_header
  printf '\n'
  if [[ -n "$title" ]]; then
    printf '  %s%s%s\n' "$C_BOLD$C_WHITE" "$title" "$C_RESET"
  fi
  if [[ -n "$subtitle" ]]; then
    printf '  %s%s%s\n' "$C_DIM" "$subtitle" "$C_RESET"
  fi
  printf '\n'
}

tui_footer() {
  printf '\n  %s%s%s\n' "$C_DIM" "v${APP_VERSION} · Developed by ${APP_AUTHOR}" "$C_RESET"
  printf '  %s%s%s\n' "$C_DIM" "With thanks to Nyr and the WireGuard project" "$C_RESET"
}

tui_menu_render() {
  local prompt="$1" selected="$2"
  shift 2
  local -a items=("$@")
  local count=${#items[@]} i item label desc
  TUI_MENU_LINES=$((count * 2 + 6))

  tui_box_top
  tui_box_row "  ${prompt}" "$C_BOLD$C_WHITE"
  tui_box_sep
  for ((i = 0; i < count; i++)); do
    item="${items[i]}"
    label="${item%%|*}"
    desc=""
    if [[ "$item" == *"|"* ]]; then
      desc="${item#*|}"
    fi
    if (( selected >= 0 && i == selected )); then
      tui_box_row "  ${TUI_CURSOR} $((i + 1))  ${label}" "$C_CYAN$C_BOLD"
    else
      tui_box_row "    $((i + 1))  ${label}" ""
    fi
    if [[ -n "$desc" ]]; then
      tui_box_row "        ${desc}" "$C_DIM"
    else
      tui_box_blank
    fi
  done
  tui_box_sep
  if [[ "$TUI_CAN_KEY" -eq 1 && "$TUI_PREVIEW" -ne 1 ]]; then
    tui_box_row "  ${TUI_UP}/${TUI_DOWN} move · Enter select · q quit" "$C_DIM"
  else
    tui_box_row "  Enter a number · q to quit" "$C_DIM"
  fi
  tui_box_bottom
}

tui_menu() {
  local prompt="$1"
  shift
  local -a items=("$@")
  local count=${#items[@]} selected ans
  selected=${TUI_MENU_DEFAULT:-0}
  (( selected < 0 || selected >= count )) && selected=0

  if [[ "$TUI_PREVIEW" -eq 1 ]]; then
    tui_menu_render "$prompt" "$selected" "${items[@]}"
    TUI_MENU_RESULT=$selected
    return 0
  fi

  if [[ "$TUI_CAN_KEY" -eq 1 ]]; then
    while true; do
      tui_menu_render "$prompt" "$selected" "${items[@]}"
      tui_getkey || return 1
      case "$TUI_KEY" in
        $'\e[A'|$'\eOA'|k)
          (( selected-- ))
          (( selected < 0 )) && selected=$((count - 1))
          ;;
        $'\e[B'|$'\eOB'|j)
          (( selected++ ))
          (( selected >= count )) && selected=0
          ;;
        ""|$'\r'|$'\n')
          TUI_MENU_RESULT=$selected
          return 0
          ;;
        q|Q|$'\e')
          TUI_MENU_RESULT=-1
          return 1
          ;;
        [1-9])
          if (( TUI_KEY <= count )); then
            TUI_MENU_RESULT=$((TUI_KEY - 1))
            return 0
          fi
          ;;
      esac
      printf '\033[%dA' "$TUI_MENU_LINES"
    done
  fi

  tui_menu_render "$prompt" -1 "${items[@]}"
  while true; do
    printf '\n  %sSelect [1-%d]%s ' "$C_CYAN" "$count" "$C_RESET"
    if ! tui_read_line; then
      TUI_MENU_RESULT=-1
      return 1
    fi
    ans="${TUI_LINE:-$((selected + 1))}"
    if [[ "$ans" == "q" || "$ans" == "Q" ]]; then
      TUI_MENU_RESULT=-1
      return 1
    fi
    if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= count )); then
      TUI_MENU_RESULT=$((ans - 1))
      return 0
    fi
    tui_error "Please enter a number between 1 and ${count}."
  done
}

tui_input() {
  local label="$1" default="$2" validator="$3" hint="$4"
  local value

  printf '\n  %s%s%s\n' "$C_BOLD$C_WHITE" "$label" "$C_RESET"
  if [[ -n "$hint" ]]; then
    printf '  %s%s%s\n' "$C_DIM" "$hint" "$C_RESET"
  fi

  while true; do
    if [[ -n "$default" ]]; then
      printf '  %s>%s [%s]: ' "$C_CYAN" "$C_RESET" "$default"
    else
      printf '  %s>%s ' "$C_CYAN" "$C_RESET"
    fi
    if ! tui_read_line; then
      tui_error "No terminal input is available."
      return 1
    fi
    value="${TUI_LINE:-$default}"
    if [[ "$value" == "b" || "$value" == "back" ]]; then
      TUI_INPUT_RESULT="back"
      return 2
    fi
    if [[ -z "$value" ]]; then
      tui_error "A value is required."
      continue
    fi
    if [[ -n "$validator" ]] && ! "$validator" "$value"; then
      tui_error "${hint:-That value is not valid.}"
      continue
    fi
    TUI_INPUT_RESULT="$value"
    return 0
  done
}

tui_pause() {
  [[ "$TUI_PREVIEW" -eq 1 ]] && return 0
  printf '\n  %sPress Enter to return%s ' "$C_DIM" "$C_RESET"
  tui_read_line || true
}

tui_prepare_log() {
  if ! : >>"$LOGFILE" 2>/dev/null; then
    LOGFILE="/tmp/wireguardSH.log"
    : >>"$LOGFILE" 2>/dev/null || true
  fi
}

tui_run_step() {
  local label="$1" rc=0 i=0
  shift

  if [[ "$TUI_DRY_RUN" -eq 1 ]]; then
    printf '  %s[%s]%s %s\n' "$C_DIM" "dry-run" "$C_RESET" "$label"
    printf '  %s%s%s\n' "$C_DIM" "$*" "$C_RESET"
    return 0
  fi

  tui_prepare_log

  if [[ "$TUI_TTY" -ne 1 ]]; then
    printf '  ... %s\n' "$label"
    if [[ "$TUI_VERBOSE" -eq 1 ]]; then
      "$@" </dev/null 2>&1 | tee -a "$LOGFILE"
      rc=${PIPESTATUS[0]}
      if (( rc == 0 )); then
        tui_success "$label"
      else
        tui_error "$label failed. See ${LOGFILE}."
        return "$rc"
      fi
      return 0
    fi
    "$@" </dev/null >>"$LOGFILE" 2>&1
    rc=$?
    if (( rc == 0 )); then
      tui_success "$label"
      return 0
    fi
    tui_error "$label failed. See ${LOGFILE}."
    return "$rc"
  fi

  if [[ "$TUI_VERBOSE" -eq 1 ]]; then
    printf '  %s%s%s %s\n' "$C_DIM" "···" "$C_RESET" "$label"
    "$@" </dev/null 2>&1 | tee -a "$LOGFILE"
    rc=${PIPESTATUS[0]}
    if (( rc == 0 )); then
      tui_success "$label"
    else
      tui_error "$label failed. See ${LOGFILE}."
      return "$rc"
    fi
    return 0
  fi

  "$@" </dev/null >>"$LOGFILE" 2>&1 &
  TUI_CHILD_PID=$!
  while kill -0 "$TUI_CHILD_PID" 2>/dev/null; do
    printf '\r\033[K  %s%s%s %s' "$C_CYAN" "${TUI_SPINNER[i]}" "$C_RESET" "$label"
    sleep 0.12
    (( i = (i + 1) % ${#TUI_SPINNER[@]} ))
  done
  wait "$TUI_CHILD_PID"
  rc=$?
  TUI_CHILD_PID=""
  if (( rc == 0 )); then
    printf '\r\033[K  %s%s%s %s\n' "$C_GREEN" "$TUI_CHECK" "$C_RESET" "$label"
    return 0
  fi
  printf '\r\033[K  %s%s%s %s\n' "$C_RED" "$TUI_CROSS" "$C_RESET" "$label"
  tui_error "The last lines of ${LOGFILE} may explain why:"
  tail -n 12 "$LOGFILE" 2>/dev/null | while IFS= read -r line; do
    printf '      %s\n' "$line"
  done
  return "$rc"
}

first_global_ipv4() {
  ip -4 -o addr show scope global 2>/dev/null | awk 'NR == 1 { split($4, a, "/"); print a[1] }'
}

first_global_ipv6() {
  ip -6 -o addr show scope global 2>/dev/null | awk '$4 ~ /^[23]/ { split($4, a, "/"); print a[1]; exit }'
}

get_system_resolvers() {
  local resolv_conf="/etc/resolv.conf" found
  if grep -q '^nameserver 127.0.0.53' "$resolv_conf" 2>/dev/null; then
    resolv_conf="/run/systemd/resolve/resolv.conf"
  fi
  found="$(grep -v '^#\|^;' "$resolv_conf" 2>/dev/null | grep '^nameserver' | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | xargs | sed -e 's/ /, /g')"
  if [[ -z "$found" ]]; then
    found="1.1.1.1, 1.0.0.1"
  fi
  printf '%s' "$found"
}

valid_client_name() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

valid_new_client_name() {
  valid_client_name "$1" && ! grep -q "^# BEGIN_PEER $1$" /etc/wireguard/wg0.conf 2>/dev/null
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  local value=$((10#$1))
  (( value >= 1 && value <= 65535 ))
}

valid_host_or_ip() {
  [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]]
}

select_dns() {
  TUI_MENU_DEFAULT=0
  tui_menu "Which DNS resolver should clients use?" \
    "Current system resolvers|Read the nameservers from /etc/resolv.conf" \
    "Google|8.8.8.8 and 8.8.4.4" \
    "Cloudflare|1.1.1.1 and 1.0.0.1" \
    "OpenDNS|208.67.222.222 and 208.67.220.220" \
    "Quad9|9.9.9.9 and 149.112.112.112" \
    "AdGuard|94.140.14.14 and 94.140.15.15" \
    "Back|Return to the previous step"
  local rc=$?
  TUI_MENU_DEFAULT=0
  (( rc != 0 )) && return 2

  case "$TUI_MENU_RESULT" in
    0) dns="$(get_system_resolvers)"; dns_label="System resolvers" ;;
    1) dns="8.8.8.8, 8.8.4.4"; dns_label="Google" ;;
    2) dns="1.1.1.1, 1.0.0.1"; dns_label="Cloudflare" ;;
    3) dns="208.67.222.222, 208.67.220.220"; dns_label="OpenDNS" ;;
    4) dns="9.9.9.9, 149.112.112.112"; dns_label="Quad9" ;;
    5) dns="94.140.14.14, 94.140.15.15"; dns_label="AdGuard" ;;
    6) return 2 ;;
  esac
  return 0
}

new_client_setup() {
  local octet=2 key psk
  while grep '^AllowedIPs' /etc/wireguard/wg0.conf | grep -q "10.7.0.${octet}/32"; do
    (( octet++ ))
  done
  if (( octet >= 255 )); then
    tui_error "253 clients are already configured. The WireGuard subnet is full."
    return 1
  fi

  key="$(wg genkey)"
  psk="$(wg genpsk)"

  cat <<EOF >>/etc/wireguard/wg0.conf
# BEGIN_PEER ${client}
[Peer]
PublicKey = $(wg pubkey <<<"$key")
PresharedKey = ${psk}
AllowedIPs = 10.7.0.${octet}/32$(grep -q 'fddd:2c4:2c4:2c4::1' /etc/wireguard/wg0.conf && echo ", fddd:2c4:2c4:2c4::${octet}/128")
# END_PEER ${client}
EOF

  cat <<EOF >"$HOME/${client}.conf"
[Interface]
Address = 10.7.0.${octet}/24$(grep -q 'fddd:2c4:2c4:2c4::1' /etc/wireguard/wg0.conf && echo ", fddd:2c4:2c4:2c4::${octet}/64")
DNS = ${dns}
PrivateKey = ${key}

[Peer]
PublicKey = $(grep PrivateKey /etc/wireguard/wg0.conf | cut -d " " -f 3 | wg pubkey)
PresharedKey = ${psk}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $(grep '^# ENDPOINT' /etc/wireguard/wg0.conf | cut -d " " -f 3):$(grep ListenPort /etc/wireguard/wg0.conf | cut -d " " -f 3)
PersistentKeepalive = 25
EOF
  chmod 600 "$HOME/${client}.conf"
}

apply_client_peer() {
  wg addconf wg0 <(sed -n "/^# BEGIN_PEER ${client}$/,/^# END_PEER ${client}$/p" /etc/wireguard/wg0.conf)
}

install_distro_packages() {
  if [[ ! "$is_container" -eq 0 ]]; then
    case "$os" in
      ubuntu)
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard qrencode $firewall
        ;;
      debian)
        if [[ "$os_version" -eq 10 ]]; then
          if ! grep -qs '^deb .* buster-backports main' /etc/apt/sources.list /etc/apt/sources.list.d/*.list; then
            echo "deb http://deb.debian.org/debian buster-backports main" >>/etc/apt/sources.list
          fi
          DEBIAN_FRONTEND=noninteractive apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y linux-headers-"$(uname -r)"
          architecture="$(dpkg --get-selections 'linux-image-*-*' | cut -f 1 | grep -oE '[^-]*$' -m 1)"
          DEBIAN_FRONTEND=noninteractive apt-get install -y linux-headers-"$architecture"
          DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard qrencode $firewall
        else
          DEBIAN_FRONTEND=noninteractive apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard qrencode $firewall
        fi
        ;;
      centos)
        if [[ "$os_version" -eq 8 ]]; then
          dnf install -y epel-release elrepo-release
          dnf install -y kmod-wireguard wireguard-tools qrencode $firewall
        else
          yum install -y epel-release https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
          yum install -y yum-plugin-elrepo
          yum install -y kmod-wireguard wireguard-tools qrencode $firewall
        fi
        mkdir -p /etc/wireguard/
        ;;
      fedora)
        dnf install -y wireguard-tools qrencode $firewall
        mkdir -p /etc/wireguard/
        ;;
    esac
    return 0
  fi

  case "$os" in
    ubuntu)
      DEBIAN_FRONTEND=noninteractive apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y qrencode ca-certificates $cron $firewall
      DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-tools --no-install-recommends
      ;;
    debian)
      if [[ "$os_version" -eq 10 ]]; then
        if ! grep -qs '^deb .* buster-backports main' /etc/apt/sources.list /etc/apt/sources.list.d/*.list; then
          echo "deb http://deb.debian.org/debian buster-backports main" >>/etc/apt/sources.list
        fi
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y qrencode ca-certificates $cron $firewall
        DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-tools --no-install-recommends
      else
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y qrencode ca-certificates $cron $firewall
        DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-tools --no-install-recommends
      fi
      ;;
    centos)
      if [[ "$os_version" -eq 8 ]]; then
        dnf install -y epel-release
        dnf install -y wireguard-tools qrencode ca-certificates tar $cron $firewall
      else
        yum install -y epel-release
        yum install -y wireguard-tools qrencode ca-certificates tar $cron $firewall
      fi
      mkdir -p /etc/wireguard/
      ;;
    fedora)
      dnf install -y wireguard-tools qrencode ca-certificates tar $cron $firewall
      mkdir -p /etc/wireguard/
      ;;
  esac
}

install_boringtun() {
  { wget -qO- https://wg.nyr.be/1/latest/download 2>/dev/null || curl -sL https://wg.nyr.be/1/latest/download; } | tar xz -C /usr/local/sbin/ --wildcards 'boringtun-*/boringtun' --strip-components 1
  mkdir -p /etc/systemd/system/wg-quick@wg0.service.d/
  cat <<'EOF' >/etc/systemd/system/wg-quick@wg0.service.d/boringtun.conf
[Service]
Environment=WG_QUICK_USERSPACE_IMPLEMENTATION=boringtun
Environment=WG_SUDO=1
EOF
  if [[ -n "$cron" ]]; then
    case "$os" in
      centos|fedora) systemctl enable --now crond.service ;;
      debian|ubuntu) systemctl enable --now cron.service ;;
    esac
  fi
}

write_server_config() {
  mkdir -p /etc/wireguard
  cat <<EOF >/etc/wireguard/wg0.conf
# Do not alter the commented lines
# They are used by wireguard.sh
# ENDPOINT $([[ -n "${public_ip:-}" ]] && echo "$public_ip" || echo "$ip")

[Interface]
Address = 10.7.0.1/24$([[ -n "${ip6:-}" ]] && echo ", fddd:2c4:2c4:2c4::1/64")
PrivateKey = $(wg genkey)
ListenPort = ${port}

EOF
  chmod 600 /etc/wireguard/wg0.conf
}

enable_forwarding() {
  echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/30-wireguard-forward.conf
  echo 1 >/proc/sys/net/ipv4/ip_forward
  if [[ -n "${ip6:-}" ]]; then
    echo 'net.ipv6.conf.all.forwarding=1' >>/etc/sysctl.d/30-wireguard-forward.conf
    echo 1 >/proc/sys/net/ipv6/conf/all/forwarding
  fi
}

apply_firewall_rules() {
  if systemctl is-active --quiet firewalld.service; then
    firewall-cmd --add-port="${port}"/udp
    firewall-cmd --zone=trusted --add-source=10.7.0.0/24
    firewall-cmd --permanent --add-port="${port}"/udp
    firewall-cmd --permanent --zone=trusted --add-source=10.7.0.0/24
    firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to "$ip"
    firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to "$ip"
    if [[ -n "${ip6:-}" ]]; then
      firewall-cmd --zone=trusted --add-source=fddd:2c4:2c4:2c4::/64
      firewall-cmd --permanent --zone=trusted --add-source=fddd:2c4:2c4:2c4::/64
      firewall-cmd --direct --add-rule ipv6 nat POSTROUTING 0 -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to "$ip6"
      firewall-cmd --permanent --direct --add-rule ipv6 nat POSTROUTING 0 -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to "$ip6"
    fi
    return 0
  fi

  local iptables_path ip6tables_path
  iptables_path="$(command -v iptables)"
  ip6tables_path="$(command -v ip6tables)"
  if [[ "$(systemd-detect-virt 2>/dev/null || true)" == "openvz" ]] && readlink -f "$(command -v iptables)" | grep -q "nft" && hash iptables-legacy 2>/dev/null; then
    iptables_path="$(command -v iptables-legacy)"
    ip6tables_path="$(command -v ip6tables-legacy)"
  fi

  cat <<EOF >/etc/systemd/system/wg-iptables.service
[Unit]
Before=network.target
[Service]
Type=oneshot
ExecStart=${iptables_path} -t nat -A POSTROUTING -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to ${ip}
ExecStart=${iptables_path} -I INPUT -p udp --dport ${port} -j ACCEPT
ExecStart=${iptables_path} -I FORWARD -s 10.7.0.0/24 -j ACCEPT
ExecStart=${iptables_path} -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=${iptables_path} -t nat -D POSTROUTING -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to ${ip}
ExecStop=${iptables_path} -D INPUT -p udp --dport ${port} -j ACCEPT
ExecStop=${iptables_path} -D FORWARD -s 10.7.0.0/24 -j ACCEPT
ExecStop=${iptables_path} -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF
  if [[ -n "${ip6:-}" ]]; then
    cat <<EOF >>/etc/systemd/system/wg-iptables.service
ExecStart=${ip6tables_path} -t nat -A POSTROUTING -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to ${ip6}
ExecStart=${ip6tables_path} -I FORWARD -s fddd:2c4:2c4:2c4::/64 -j ACCEPT
ExecStart=${ip6tables_path} -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=${ip6tables_path} -t nat -D POSTROUTING -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to ${ip6}
ExecStop=${ip6tables_path} -D FORWARD -s fddd:2c4:2c4:2c4::/64 -j ACCEPT
ExecStop=${ip6tables_path} -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF
  fi
  cat <<'EOF' >>/etc/systemd/system/wg-iptables.service
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable --now wg-iptables.service
}

install_boringtun_updater() {
  cat <<'EOF' >/usr/local/sbin/boringtun-upgrade
#!/bin/bash
latest=$(wget -qO- https://wg.nyr.be/1/latest 2>/dev/null || curl -sL https://wg.nyr.be/1/latest 2>/dev/null)
if ! head -1 <<<"$latest" | grep -qiE "^boringtun.+[0-9]+\.[0-9]+.*$"; then
  echo "Update server unavailable"
  exit
fi
current=$(boringtun -V)
if [[ "$current" != "$latest" ]]; then
  download="https://wg.nyr.be/1/latest/download"
  xdir=$(mktemp -d)
  if { wget -qO- "$download" 2>/dev/null || curl -sL "$download"; } | tar xz -C "$xdir" --wildcards "boringtun-*/boringtun" --strip-components 1; then
    systemctl stop wg-quick@wg0.service
    rm -f /usr/local/sbin/boringtun
    mv "$xdir"/boringtun /usr/local/sbin/boringtun
    systemctl start wg-quick@wg0.service
    echo "Successfully updated to $(boringtun -V)"
  else
    echo "boringtun update failed"
  fi
  rm -rf "$xdir"
else
  echo "$current is up to date"
fi
EOF
  chmod +x /usr/local/sbin/boringtun-upgrade
  { crontab -l 2>/dev/null; echo "$((RANDOM % 60)) $((RANDOM % 3 + 3)) * * * /usr/local/sbin/boringtun-upgrade &>/dev/null"; } | crontab -
}

install_kernel_warning_check() {
  kernel_warning=""
  if [[ ! "$is_container" -eq 0 ]] && ! modprobe -nq wireguard 2>/dev/null; then
    kernel_warning="Installation finished, but the WireGuard kernel module could not load."
  fi
}

install_wireguard() {
  tui_prepare_log
  tui_screen_start "Installing WireGuard" "This can take a minute. The full log is at ${LOGFILE}."
  tui_paragraph "Nothing is hidden: package output is written to the log, and each step is reported here as it finishes."
  printf '\n'

  tui_run_step "Updating packages and installing WireGuard" install_distro_packages || return 1

  if [[ "$is_container" -eq 0 ]]; then
    tui_run_step "Downloading BoringTun" install_boringtun || return 1
  fi

  if [[ "$firewall" == "firewalld" ]]; then
    tui_run_step "Enabling firewalld" systemctl enable --now firewalld.service || return 1
  fi

  tui_run_step "Writing /etc/wireguard/wg0.conf" write_server_config || return 1
  tui_run_step "Enabling IP forwarding" enable_forwarding || return 1
  tui_run_step "Configuring firewall and NAT" apply_firewall_rules || return 1
  tui_run_step "Creating the first client, ${client}" new_client_setup || return 1
  tui_run_step "Starting wg-quick@wg0" systemctl enable --now wg-quick@wg0.service || return 1

  if [[ "$boringtun_updates" =~ ^[yY]$ && "$is_container" -eq 0 ]]; then
    tui_run_step "Installing the BoringTun updater" install_boringtun_updater || return 1
  fi

  install_kernel_warning_check
  return 0
}

show_qr() {
  printf '\n'
  tui_section "Scan to connect"
  if command -v qrencode >/dev/null 2>&1 && [[ -f "$HOME/${client}.conf" ]]; then
    qrencode -t UTF8 <"$HOME/${client}.conf"
    printf '\n  %sThe QR code contains this client configuration.%s\n' "$C_DIM" "$C_RESET"
  else
    tui_warn "qrencode is not available. Import ${HOME}/${client}.conf manually."
  fi
}

show_success() {
  local rc
  while true; do
    tui_screen_start "WireGuard is ready" "Your server is installed and listening."
    tui_box_top
    tui_box_kv "Status" "active"
    tui_box_kv "Endpoint" "$([[ -n "${public_ip:-}" ]] && echo "$public_ip" || echo "$ip"):${port}/udp"
    tui_box_kv "First client" "$client"
    tui_box_kv "Config" "$HOME/${client}.conf"
    tui_box_kv "Interface" "wg0"
    tui_box_bottom

    if [[ -n "${kernel_warning:-}" ]]; then
      printf '\n'
      tui_warn "$kernel_warning"
      case "$os" in
        ubuntu)
          if [[ "$os_version" -eq 1804 ]]; then
            tui_paragraph "Upgrade the kernel and headers with \"apt-get install linux-generic\", then restart."
          fi
          ;;
        debian)
          if [[ "$os_version" -eq 10 ]]; then
            tui_paragraph "Upgrade the kernel with \"apt-get install linux-image-${architecture}\", then restart."
          fi
          ;;
        centos)
          if [[ "$os_version" -le 8 ]]; then
            tui_paragraph "Reboot the server to load the most recent kernel."
          fi
          ;;
      esac
    fi

    show_qr
    tui_footer

    TUI_MENU_DEFAULT=0
    tui_menu "What would you like to do next?" \
      "Add another client|Create a configuration for another device" \
      "About & credits|The people behind WireGuard and this installer" \
      "Exit|Leave the installer"
    rc=$?
    TUI_MENU_DEFAULT=0
    (( rc != 0 )) && return
    case "$TUI_MENU_RESULT" in
      0) add_client_flow; continue ;;
      1) screen_about; continue ;;
      2) return ;;
    esac
    return
  done
}

read_management_state() {
  local conf="/etc/wireguard/wg0.conf"
  wg_port="$(grep '^ListenPort' "$conf" 2>/dev/null | awk '{print $3}')"
  wg_endpoint="$(grep '^# ENDPOINT' "$conf" 2>/dev/null | awk '{print $3}')"
  wg_clients="$(grep -c '^# BEGIN_PEER' "$conf" 2>/dev/null || true)"
  [[ "$wg_clients" =~ ^[0-9]+$ ]] || wg_clients=0
  if grep -q 'fddd:2c4:2c4:2c4::1' "$conf" 2>/dev/null; then
    wg_ipv6="enabled"
  else
    wg_ipv6="disabled"
  fi
  if systemctl is-active --quiet wg-quick@wg0.service; then
    wg_status="active"
    wg_status_color="$C_GREEN"
  else
    wg_status="inactive"
    wg_status_color="$C_RED"
  fi
  [[ -n "$wg_port" ]] || wg_port="unknown"
  [[ -n "$wg_endpoint" ]] || wg_endpoint="unknown"
}

dashboard_screen() {
  tui_screen_start "Dashboard" "WireGuard is already installed on this server."
  tui_box_top
  tui_box_kv "Status" "$wg_status"
  tui_box_kv "Interface" "wg0"
  tui_box_kv "Endpoint" "${wg_endpoint}:${wg_port}/udp"
  tui_box_kv "Clients" "$wg_clients"
  tui_box_kv "IPv6" "$wg_ipv6"
  tui_box_kv "Config" "/etc/wireguard/wg0.conf"
  tui_box_bottom
  printf '\n'
  tui_note "$wg_status_color" "$TUI_DOT" "Service ${wg_status}."
  tui_footer
  TUI_MENU_DEFAULT=0
  tui_menu "What would you like to do?" \
    "Add a new client|Create a config and QR code for another device" \
    "Remove an existing client|Revoke one device without touching the server" \
    "Remove WireGuard|Stop the service and remove the installation" \
    "About & credits|The people behind WireGuard and this installer" \
    "Exit|Close the installer"
  local rc=$?
  TUI_MENU_DEFAULT=0
  return "$rc"
}

add_client_flow() {
  local rc
  tui_screen_start "Add a client" "Step 1 of 2 · choose a name and DNS resolver."
  tui_input "Name for the new client" "" valid_new_client_name "Letters, numbers, hyphens and underscores. The name must be unique."
  rc=$?
  (( rc == 2 )) && return 2
  (( rc != 0 )) && return 1
  client="$TUI_INPUT_RESULT"

  select_dns
  rc=$?
  (( rc == 2 )) && return 2
  (( rc != 0 )) && return 1

  tui_screen_start "Review the new client" "Step 2 of 2 · nothing has changed yet."
  tui_box_top
  tui_box_kv "Client" "$client"
  tui_box_kv "DNS" "${dns_label} (${dns})"
  tui_box_kv "Config" "$HOME/${client}.conf"
  tui_box_bottom
  printf '\n'
  TUI_MENU_DEFAULT=0
  tui_menu "Create this client?" \
    "Create client|Add the peer and write the configuration" \
    "Back|Return without creating the client"
  rc=$?
  TUI_MENU_DEFAULT=0
  (( rc != 0 )) && return 2
  (( TUI_MENU_RESULT != 0 )) && return 2

  tui_screen_start "Adding ${client}" "Writing the peer and client configuration."
  printf '\n'
  tui_run_step "Creating the client configuration" new_client_setup || return 1
  tui_run_step "Applying the peer to wg0" apply_client_peer || return 1

  tui_screen_start "Client added" "${client} is ready to connect."
  tui_box_top
  tui_box_kv "Client" "$client"
  tui_box_kv "Config" "$HOME/${client}.conf"
  tui_box_kv "DNS" "${dns_label}"
  tui_box_bottom
  show_qr

  TUI_MENU_DEFAULT=0
  tui_menu "What next?" \
    "Add another client|Create another configuration" \
    "Done|Return to the dashboard"
  rc=$?
  TUI_MENU_DEFAULT=0
  (( rc != 0 )) && return 2
  if (( TUI_MENU_RESULT == 0 )); then
    add_client_flow
  fi
  return 0
}

remove_client_peer() {
  local public_key
  public_key="$(sed -n "/^# BEGIN_PEER ${client}$/,/^# END_PEER ${client}$/p" /etc/wireguard/wg0.conf | grep -m 1 '^PublicKey' | awk '{print $3}')"
  if [[ -n "$public_key" ]]; then
    wg set wg0 peer "$public_key" remove 2>/dev/null || true
  fi
  sed -i "/^# BEGIN_PEER ${client}$/,/^# END_PEER ${client}$/d" /etc/wireguard/wg0.conf
}

remove_client_flow() {
  local conf="/etc/wireguard/wg0.conf" rc i line
  local -a clients=() items=()

  while IFS= read -r line; do
    [[ -n "$line" ]] && clients+=("$line")
  done < <(grep '^# BEGIN_PEER' "$conf" 2>/dev/null | awk '{print $3}')

  if (( ${#clients[@]} == 0 )); then
    tui_screen_start "Remove a client" "There are no clients to remove."
    tui_warn "Run the installer again to add a client first."
    tui_pause
    return 0
  fi

  for ((i = 0; i < ${#clients[@]}; i++)); do
    items+=("${clients[i]}|Peer ${clients[i]}")
  done
  items+=("Back|Return to the dashboard")

  tui_screen_start "Remove a client" "Step 1 of 2 · choose a client to remove."
  TUI_MENU_DEFAULT=0
  tui_menu "Which client should be removed?" "${items[@]}"
  rc=$?
  TUI_MENU_DEFAULT=0
  (( rc != 0 )) && return 2
  (( TUI_MENU_RESULT == ${#clients[@]} )) && return 2
  client="${clients[TUI_MENU_RESULT]}"

  tui_screen_start "Remove ${client}?" "Step 2 of 2 · this cannot be undone."
  tui_warn "The peer is removed from the live interface and from wg0.conf. The local client file is left in place."
  TUI_MENU_DEFAULT=1
  tui_menu "Remove ${client}?" \
    "Yes, remove ${client}|Revoke this client's access" \
    "No, keep ${client}|Return to the dashboard"
  rc=$?
  TUI_MENU_DEFAULT=0
  (( rc != 0 )) && return 2
  (( TUI_MENU_RESULT != 0 )) && return 2

  tui_screen_start "Removing ${client}" "Revoking the peer and updating wg0.conf."
  printf '\n'
  tui_run_step "Removing ${client}" remove_client_peer || return 1

  tui_screen_start "Client removed" "${client} no longer has access."
  tui_paragraph "The local file ${HOME}/${client}.conf was left in place. Delete it as well if you no longer need it."
  tui_pause
  return 0
}

stop_wireguard_services() {
  systemctl disable --now wg-quick@wg0.service 2>/dev/null || true
  systemctl disable --now wg-iptables.service 2>/dev/null || true
}

remove_firewall_rules() {
  local saved_ip="$ip" saved_ip6="$ip6" saved_port="$port"
  if systemctl is-active --quiet firewalld.service; then
    saved_ip="$(firewall-cmd --direct --get-rules ipv4 nat POSTROUTING | grep '\-s 10.7.0.0/24 '"'"'!'"'"' -d 10.7.0.0/24' | grep -oE '[^ ]+$')"
    firewall-cmd --remove-port="${saved_port}"/udp 2>/dev/null || true
    firewall-cmd --zone=trusted --remove-source=10.7.0.0/24 2>/dev/null || true
    firewall-cmd --permanent --remove-port="${saved_port}"/udp 2>/dev/null || true
    firewall-cmd --permanent --zone=trusted --remove-source=10.7.0.0/24 2>/dev/null || true
    if [[ -n "$saved_ip" ]]; then
      firewall-cmd --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to "$saved_ip" 2>/dev/null || true
      firewall-cmd --permanent --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to "$saved_ip" 2>/dev/null || true
    fi
    if grep -qs 'fddd:2c4:2c4:2c4::1/64' /etc/wireguard/wg0.conf 2>/dev/null; then
      saved_ip6="$(firewall-cmd --direct --get-rules ipv6 nat POSTROUTING | grep '\-s fddd:2c4:2c4:2c4::/64 '"'"'!'"'"' -d fddd:2c4:2c4:2c4::/64' | grep -oE '[^ ]+$')"
      firewall-cmd --zone=trusted --remove-source=fddd:2c4:2c4:2c4::/64 2>/dev/null || true
      firewall-cmd --permanent --zone=trusted --remove-source=fddd:2c4:2c4:2c4::/64 2>/dev/null || true
      if [[ -n "$saved_ip6" ]]; then
        firewall-cmd --direct --remove-rule ipv6 nat POSTROUTING 0 -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to "$saved_ip6" 2>/dev/null || true
        firewall-cmd --permanent --direct --remove-rule ipv6 nat POSTROUTING 0 -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to "$saved_ip6" 2>/dev/null || true
      fi
    fi
    return 0
  fi
  rm -f /etc/systemd/system/wg-iptables.service
  systemctl daemon-reload 2>/dev/null || true
}

remove_wireguard_packages() {
  if [[ ! "$is_container" -eq 0 ]]; then
    case "$os" in
      ubuntu)
        rm -rf /etc/wireguard/
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y wireguard wireguard-tools 2>/dev/null || true
        ;;
      debian)
        rm -rf /etc/wireguard/
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y wireguard wireguard-dkms wireguard-tools 2>/dev/null || true
        ;;
      centos)
        rm -rf /etc/wireguard/
        if [[ "$os_version" -eq 8 ]]; then
          dnf remove -y kmod-wireguard wireguard-tools 2>/dev/null || true
        else
          yum remove -y kmod-wireguard wireguard-tools 2>/dev/null || true
        fi
        ;;
      fedora)
        rm -rf /etc/wireguard/
        dnf remove -y wireguard-tools 2>/dev/null || true
        ;;
    esac
    return 0
  fi

  { crontab -l 2>/dev/null | grep -v '/usr/local/sbin/boringtun-upgrade'; } | crontab - 2>/dev/null || true
  case "$os" in
    ubuntu|debian)
      rm -rf /etc/wireguard/
      DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y wireguard-tools 2>/dev/null || true
      ;;
    centos)
      rm -rf /etc/wireguard/
      if [[ "$os_version" -eq 8 ]]; then
        dnf remove -y wireguard-tools 2>/dev/null || true
      else
        yum remove -y wireguard-tools 2>/dev/null || true
      fi
      ;;
    fedora)
      rm -rf /etc/wireguard/
      dnf remove -y wireguard-tools 2>/dev/null || true
      ;;
  esac
  rm -f /usr/local/sbin/boringtun /usr/local/sbin/boringtun-upgrade
}

cleanup_wireguard_files() {
  rm -f /etc/systemd/system/wg-quick@wg0.service.d/boringtun.conf
  rmdir /etc/systemd/system/wg-quick@wg0.service.d 2>/dev/null || true
  rm -f /etc/sysctl.d/30-wireguard-forward.conf
  systemctl daemon-reload 2>/dev/null || true
}

remove_wireguard_flow() {
  local rc
  tui_screen_start "Remove WireGuard" "This is the point of no return."
  tui_warn "This removes WireGuard, /etc/wireguard, the firewall and NAT rules, the BoringTun updater, and the server-side configuration. Client files in ${HOME} are left in place."
  tui_paragraph "If you only need to revoke one device, go back and use \"Remove an existing client\" instead."
  TUI_MENU_DEFAULT=1
  tui_menu "Remove WireGuard from this server?" \
    "Remove WireGuard|Stop services and remove packages and configuration" \
    "Cancel|Keep everything as it is"
  rc=$?
  TUI_MENU_DEFAULT=0
  (( rc != 0 )) && return 2
  (( TUI_MENU_RESULT != 0 )) && return 2

  port="$(grep '^ListenPort' /etc/wireguard/wg0.conf | awk '{print $3}')"
  ip="$(first_global_ipv4)"
  ip6=""
  if grep -qs 'fddd:2c4:2c4:2c4::1/64' /etc/wireguard/wg0.conf; then
    ip6="$(first_global_ipv6)"
  fi

  tui_screen_start "Removing WireGuard" "Stopping services and cleaning up."
  printf '\n'
  tui_run_step "Stopping WireGuard services" stop_wireguard_services || true
  tui_run_step "Removing firewall rules" remove_firewall_rules || true
  tui_run_step "Removing packages and configuration" remove_wireguard_packages || true
  tui_run_step "Cleaning up service files" cleanup_wireguard_files || true

  tui_screen_start "WireGuard removed" "The server has been returned to its pre-install state."
  tui_paragraph "Client configuration files in ${HOME} were left in place. Remove them separately if you no longer need them."
  tui_pause
  return 0
}

management_loop() {
  local rc
  while true; do
    [[ -e /etc/wireguard/wg0.conf ]] || return 0
    read_management_state
    dashboard_screen
    rc=$?
    (( rc != 0 )) && return 0
    case "$TUI_MENU_RESULT" in
      0) add_client_flow ;;
      1) remove_client_flow ;;
      2) if remove_wireguard_flow; then return 0; fi ;;
      3) screen_about ;;
      4) return 0 ;;
    esac
  done
}

screen_about() {
  tui_screen_start "About & credits" "With gratitude, not ownership."
  tui_paragraph "${APP_NAME} is an independent installer developed and maintained by ${APP_AUTHOR}. We take no credit for WireGuard itself, and we are grateful to the people whose work makes this possible."
  printf '  %s%s%s\n' "$C_CYAN" "$APP_AUTHOR_URL" "$C_RESET"
  tui_section "WireGuard"
  tui_paragraph "Created by Jason A. Donenfeld and the WireGuard project. The protocol, kernel module, tools, and documentation are their work."
  printf '  %s%s%s\n' "$C_CYAN" "$WIREGUARD_URL" "$C_RESET"
  tui_section "wireguard-install"
  tui_paragraph "The guided flow builds on Nyr's excellent wireguard-install. Thank you, Nyr, for the careful work and the generous licence that made this possible."
  printf '  %s%s%s\n' "$C_CYAN" "$UPSTREAM_URL" "$C_RESET"
  tui_section "Independence"
  tui_paragraph "${APP_NAME} is not affiliated with, endorsed by, or supported by the WireGuard project or Nyr. Any mistakes in this installer are ours alone."
  tui_section "Licence & source"
  tui_paragraph "The installer is GPL-3.0. Source, issues, and releases are on GitHub."
  printf '  %s%s%s\n' "$C_CYAN" "$APP_REPO_URL" "$C_RESET"
  tui_footer
  tui_pause
}

welcome_screen() {
  local primary
  primary="$(first_global_ipv4)"
  while true; do
    tui_screen_start "Welcome" "A guided install, with every step in plain sight."
    tui_box_top
    tui_box_kv "System" "$os_label"
    tui_box_kv "Host" "$(hostname 2>/dev/null || echo unknown)"
    tui_box_kv "Primary IPv4" "${primary:-not detected}"
    tui_box_kv "WireGuard" "not installed"
    tui_box_kv "VPN subnet" "10.7.0.0/24"
    tui_box_bottom
    printf '\n'
    tui_paragraph "This wizard installs WireGuard, configures forwarding and a firewall, and creates your first client. Nothing changes until you review the choices and confirm."
    printf '\n'
    tui_note "$C_DIM" "$TUI_BULLET" "With thanks to Nyr for wireguard-install, and to Jason A. Donenfeld and the WireGuard project for WireGuard itself."
    tui_footer
    TUI_MENU_DEFAULT=0
    tui_menu "What would you like to do?" \
      "Start guided setup|Review the settings before anything changes" \
      "About & credits|Meet the people whose work this builds on" \
      "Exit|Leave the server untouched"
    local rc=$?
    TUI_MENU_DEFAULT=0
    (( rc != 0 )) && return 1
    case "$TUI_MENU_RESULT" in
      0) return 0 ;;
      1) screen_about ;;
      2) return 1 ;;
    esac
  done
}

wizard_network() {
  local row line rc detected
  local -a rows=() items=() rows6=() items6=()

  tui_screen_start "Network" "Step 1 of 5 · choose how clients reach this server."
  while IFS= read -r line; do
    [[ -n "$line" ]] && rows+=("$line")
  done < <(ip -4 -o addr show scope global 2>/dev/null | awk '{ split($4, a, "/"); print a[1] "|" $2 }')

  if (( ${#rows[@]} == 0 )); then
    tui_error "No global IPv4 address was found."
    tui_paragraph "Connect the server to a network with a public or private IPv4 address, then run the installer again."
    tui_pause
    return 1
  fi

  if (( ${#rows[@]} == 1 )); then
    ip="${rows[0]%%|*}"
    tui_success "Using IPv4 ${ip} on ${rows[0]#*|}."
  else
    for row in "${rows[@]}"; do
      items+=("${row%%|*}|Interface ${row#*|}")
    done
    items+=("Back|Return to the previous step")
    TUI_MENU_DEFAULT=0
    tui_menu "Which IPv4 address should WireGuard use?" "${items[@]}" || return 2
    TUI_MENU_DEFAULT=0
    (( TUI_MENU_RESULT == ${#rows[@]} )) && return 2
    ip="${rows[TUI_MENU_RESULT]%%|*}"
  fi

  if echo "$ip" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
    detected="$(grep -m 1 -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' <<< "$(wget -T 10 -t 1 -4qO- "http://ip1.dynupdate.no-ip.com/" 2>/dev/null || curl -m 10 -4Ls "http://ip1.dynupdate.no-ip.com/" 2>/dev/null)")"
    tui_warn "This address is private, so the server is behind NAT."
    tui_input "Public IPv4 address or hostname" "$detected" valid_host_or_ip "Clients will connect to this address. Use the public IP or a DNS name that resolves to it."
    rc=$?
    (( rc == 2 )) && return 2
    (( rc != 0 )) && return 1
    public_ip="$TUI_INPUT_RESULT"
  fi

  while IFS= read -r line; do
    [[ -n "$line" ]] && rows6+=("$line")
  done < <(ip -6 -o addr show scope global 2>/dev/null | awk '$4 ~ /^[23]/ { split($4, a, "/"); print a[1] "|" $2 }')

  if (( ${#rows6[@]} == 0 )); then
    ip6=""
    tui_paragraph "No global IPv6 address was found. The tunnel will use IPv4 only; you can add IPv6 later."
  elif (( ${#rows6[@]} == 1 )); then
    ip6="${rows6[0]%%|*}"
    tui_success "Using IPv6 ${ip6} on ${rows6[0]#*|}."
  else
    for row in "${rows6[@]}"; do
      items6+=("${row%%|*}|Interface ${row#*|}")
    done
    items6+=("Disable IPv6|Use the tunnel over IPv4 only")
    items6+=("Back|Return to the previous step")
    TUI_MENU_DEFAULT=0
    tui_menu "Which IPv6 address should WireGuard use?" "${items6[@]}" || return 2
    TUI_MENU_DEFAULT=0
    if (( TUI_MENU_RESULT == ${#rows6[@]} )); then
      ip6=""
    elif (( TUI_MENU_RESULT == ${#rows6[@]} + 1 )); then
      return 2
    else
      ip6="${rows6[TUI_MENU_RESULT]%%|*}"
    fi
  fi

  TUI_MENU_DEFAULT=0
  tui_menu "Continue to the listen port?" \
    "Continue|Use these network settings" \
    "Back|Return to the previous step"
  rc=$?
  TUI_MENU_DEFAULT=0
  (( rc != 0 )) && return 2
  (( TUI_MENU_RESULT != 0 )) && return 2
  return 0
}

wizard_port() {
  local rc
  tui_screen_start "Listen port" "Step 2 of 5 · the UDP port clients connect to."
  tui_paragraph "WireGuard's default is 51820/udp. If you choose another port, allow it through any external firewall as well."
  tui_input "WireGuard listen port" "51820" valid_port "Enter a number between 1 and 65535."
  rc=$?
  (( rc == 2 )) && return 2
  (( rc != 0 )) && return 1
  port=$((10#$TUI_INPUT_RESULT))
  return 0
}

wizard_client() {
  local rc
  tui_screen_start "First client" "Step 3 of 5 · name the first device."
  tui_paragraph "A client configuration and QR code will be created for this device. You can add more clients later without reinstalling."
  tui_input "Name for the first client" "client" valid_client_name "Use letters, numbers, hyphens and underscores."
  rc=$?
  (( rc == 2 )) && return 2
  (( rc != 0 )) && return 1
  client="$TUI_INPUT_RESULT"
  return 0
}

wizard_dns() {
  local rc
  tui_screen_start "DNS resolver" "Step 4 of 5 · choose what clients use for DNS."
  tui_paragraph "This is written into each client configuration. The server's own resolver is untouched."
  select_dns
  rc=$?
  (( rc == 2 )) && return 2
  (( rc != 0 )) && return 1
  return 0
}

wizard_review() {
  local rc has_updates=0 back_index
  tui_screen_start "Review your setup" "Step 5 of 5 · nothing has changed yet."
  tui_box_top
  tui_box_kv "System" "$os_label"
  tui_box_kv "Endpoint" "$([[ -n "${public_ip:-}" ]] && echo "$public_ip" || echo "$ip"):${port}/udp"
  tui_box_kv "IPv4" "$ip"
  tui_box_kv "IPv6" "${ip6:-disabled}"
  tui_box_kv "First client" "$client"
  tui_box_kv "DNS" "$dns_label"
  if [[ "$is_container" -eq 0 ]]; then
    if [[ "$boringtun_updates" =~ ^[yY]$ ]]; then
      tui_box_kv "BoringTun" "automatic updates on"
    else
      tui_box_kv "BoringTun" "automatic updates off"
    fi
    tui_box_kv "Tunnel" "userspace (container)"
  else
    tui_box_kv "Tunnel" "WireGuard kernel module"
  fi
  tui_box_bottom
  printf '\n'
  tui_paragraph "Choosing Install now will install packages, write configuration, and start the WireGuard service. You can still cancel below."

  local -a items=("Install now|Install WireGuard and create the first client")
  if [[ "$is_container" -eq 0 ]]; then
    has_updates=1
    if [[ "$boringtun_updates" =~ ^[yY]$ ]]; then
      items+=("Disable BoringTun automatic updates|Currently enabled")
    else
      items+=("Enable BoringTun automatic updates|Currently disabled")
    fi
  fi
  back_index=$((1 + has_updates))
  items+=("Back|Return to the previous step")
  items+=("Cancel|Exit without changing anything")

  TUI_MENU_DEFAULT=0
  tui_menu "Ready to install?" "${items[@]}"
  rc=$?
  TUI_MENU_DEFAULT=0
  (( rc != 0 )) && return 1
  if (( TUI_MENU_RESULT == 0 )); then
    return 0
  elif (( has_updates == 1 && TUI_MENU_RESULT == 1 )); then
    if [[ "$boringtun_updates" =~ ^[yY]$ ]]; then
      boringtun_updates="n"
    else
      boringtun_updates="y"
    fi
    wizard_review
    return $?
  elif (( TUI_MENU_RESULT == back_index )); then
    return 2
  fi
  return 1
}

wizard_run() {
  local step=1 rc
  while (( step <= 5 )); do
    case "$step" in
      1) wizard_network ;;
      2) wizard_port ;;
      3) wizard_client ;;
      4) wizard_dns ;;
      5) wizard_review ;;
    esac
    rc=$?
    case "$rc" in
      0) (( step++ )) ;;
      2)
        if (( step == 1 )); then
          return 1
        fi
        (( step-- ))
        ;;
      *) return 1 ;;
    esac
  done
  return 0
}

configure_runtime_defaults() {
  firewall=""
  if ! systemctl is-active --quiet firewalld.service 2>/dev/null && ! hash iptables 2>/dev/null; then
    case "$os" in
      centos|fedora) firewall="firewalld" ;;
      debian|ubuntu) firewall="iptables" ;;
    esac
  fi

  cron=""
  if [[ "$is_container" -eq 0 && "$boringtun_updates" =~ ^[yY]$ ]]; then
    case "$os" in
      centos|fedora) cron="cronie" ;;
      debian|ubuntu) cron="cron" ;;
    esac
  fi
}

run_preflight() {
  if readlink /proc/$$/exe 2>/dev/null | grep -q "dash"; then
    tui_die "This installer needs to be run with bash, not sh." "Run it with: bash <(curl -s https://wireguard.sh/wireguard.sh)"
  fi

  if grep -qs "ubuntu" /etc/os-release 2>/dev/null; then
    os="ubuntu"
    os_version="$(grep '^VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')"
  elif [[ -e /etc/debian_version ]]; then
    os="debian"
    os_version="$(grep -oE '[0-9]+' /etc/debian_version | head -1)"
  elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version="$(grep -oE '[0-9]+' /etc/centos-release | head -1)"
  elif [[ -e /etc/fedora-release ]]; then
    os="fedora"
    os_version="$(grep -oE '[0-9]+' /etc/fedora-release | head -1)"
  else
    tui_die "This distribution is not supported." "Supported distributions are Ubuntu 18.04+, Debian 10+, CentOS 7+, and Fedora 31+."
  fi

  if [[ -r /etc/os-release ]]; then
    os_pretty="$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
  fi
  [[ -n "$os_pretty" ]] || os_pretty="$os $os_version"

  if command -v systemd-detect-virt >/dev/null 2>&1; then
    virtualization="$(systemd-detect-virt 2>/dev/null || true)"
    if systemd-detect-virt -cq 2>/dev/null; then
      is_container=0
    fi
  fi
  [[ -z "$virtualization" || "$virtualization" == "none" ]] && virtualization="bare metal"
  os_label="${os_pretty} · $(uname -m) · ${virtualization}"

  if ! [[ "$os_version" =~ ^[0-9]+$ ]]; then
    tui_die "Could not determine the distribution version." "Check /etc/os-release and run the installer again."
  fi

  if [[ "$os" == "ubuntu" && "$os_version" -lt 1804 ]]; then
    tui_die "Ubuntu 18.04 or higher is required." "This version of Ubuntu is too old and unsupported."
  fi
  if [[ "$os" == "debian" && "$os_version" -lt 10 ]]; then
    tui_die "Debian 10 or higher is required." "This version of Debian is too old and unsupported."
  fi
  if [[ "$os" == "centos" && "$os_version" -lt 7 ]]; then
    tui_die "CentOS 7 or higher is required." "This version of CentOS is too old and unsupported."
  fi
  if [[ "$os" == "fedora" && "$os_version" -lt 31 ]]; then
    tui_die "Fedora 31 or higher is required." "Upgrade Fedora before running this installer."
  fi

  if ! grep -q sbin <<<"$PATH"; then
    tui_die '$PATH does not include sbin.' 'Try using "su -" instead of "su".'
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    tui_die "systemd is required to manage WireGuard." "This installer supports systemd-based distributions only."
  fi

  if ! command -v ip >/dev/null 2>&1; then
    tui_die "The ip command is required to detect network interfaces." "Install iproute2 and run the installer again."
  fi

  if [[ "$os" == "fedora" && "$os_version" -eq 31 && "$(uname -r | cut -d "." -f 2)" -lt 6 && "$is_container" -ne 0 ]]; then
    tui_die "Fedora 31 is supported, but the kernel is outdated." 'Upgrade the kernel using "dnf upgrade kernel" and restart.'
  fi

  if [[ "$EUID" -ne 0 && "$TUI_DRY_RUN" -ne 1 ]]; then
    tui_die "This installer needs to be run with superuser privileges." "Run it as root, for example with sudo."
  fi

  if [[ "$is_container" -eq 0 && "$TUI_DRY_RUN" -ne 1 ]]; then
    if [[ "$(uname -m)" != "x86_64" ]]; then
      tui_die "In containers this installer supports only x86_64." "This system runs on $(uname -m)."
    fi
    if [[ ! -e /dev/net/tun ]] || ! ( exec 7<>/dev/net/tun ) 2>/dev/null; then
      tui_die "The TUN device is not available." "Enable TUN in the container before running this installer."
    fi
  fi

  if [[ "$os" == "debian" && "$os_version" -eq 10 ]]; then
    architecture="$(dpkg --get-selections 'linux-image-*-*' 2>/dev/null | cut -f 1 | grep -oE '[^-]*$' -m 1)"
  fi
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      -h|--help) show_help=1 ;;
      -V|--version) show_version=1 ;;
      --preview) TUI_PREVIEW=1 ;;
      --dry-run) TUI_DRY_RUN=1 ;;
      --no-color) TUI_COLOR_MODE="never" ;;
      --ascii) TUI_ASCII_MODE=1 ;;
      --verbose) TUI_VERBOSE=1 ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        printf 'Run %s --help for usage.\n' "$APP_NAME" >&2
        exit 2
        ;;
    esac
    shift
  done
}

preview_welcome() {
  tui_screen_start "Welcome" "A guided install, with every step in plain sight."
  tui_box_top
  tui_box_kv "System" "Ubuntu 24.04 · x86_64 · KVM"
  tui_box_kv "Host" "vpn.example.com"
  tui_box_kv "Primary IPv4" "203.0.113.10"
  tui_box_kv "WireGuard" "not installed"
  tui_box_kv "VPN subnet" "10.7.0.0/24"
  tui_box_bottom
  printf '\n'
  tui_paragraph "This wizard installs WireGuard, configures forwarding and a firewall, and creates your first client. Nothing changes until you review the choices and confirm."
  printf '\n'
  tui_note "$C_DIM" "$TUI_BULLET" "With thanks to Nyr for wireguard-install, and to Jason A. Donenfeld and the WireGuard project for WireGuard itself."
  tui_footer
  tui_menu "What would you like to do?" \
    "Start guided setup|Review the settings before anything changes" \
    "About & credits|Meet the people whose work this builds on" \
    "Exit|Leave the server untouched"
}

preview_tui() {
  TUI_PREVIEW=1
  TUI_NO_CLEAR=1
  TUI_CAN_KEY=0
  os_label="Ubuntu 24.04 · x86_64 · KVM"
  ip="203.0.113.10"
  ip6="2001:db8:7::10"
  port="51820"
  client="laptop"
  dns="1.1.1.1, 1.0.0.1"
  dns_label="Cloudflare"
  boringtun_updates="n"
  is_container=1
  public_ip=""

  printf '\n  %sPREVIEW 1 · WELCOME%s\n' "$C_CYAN$C_BOLD" "$C_RESET"
  preview_welcome
  printf '\n\n  %sPREVIEW 2 · REVIEW%s\n' "$C_CYAN$C_BOLD" "$C_RESET"
  wizard_review
  printf '\n\n  %sPREVIEW 3 · DASHBOARD%s\n' "$C_CYAN$C_BOLD" "$C_RESET"
  wg_status="active"
  wg_status_color="$C_GREEN"
  wg_endpoint="203.0.113.10"
  wg_port="51820"
  wg_clients="3"
  wg_ipv6="enabled"
  dashboard_screen
  printf '\n\n  %sPREVIEW 4 · ABOUT & CREDITS%s\n' "$C_CYAN$C_BOLD" "$C_RESET"
  screen_about
}

main() {
  parse_args "$@"

  if [[ "$show_help" -eq 1 ]]; then
    print_help
    exit 0
  fi
  if [[ "$show_version" -eq 1 ]]; then
    printf '%s %s\n' "$APP_NAME" "$APP_VERSION"
    exit 0
  fi

  tui_init

  if [[ "$TUI_PREVIEW" -eq 1 ]]; then
    preview_tui
    tui_cleanup
    exit 0
  fi

  run_preflight

  if [[ -e /etc/wireguard/wg0.conf ]]; then
    management_loop
    tui_cleanup
    exit 0
  fi

  while true; do
    if ! welcome_screen; then
      tui_cleanup
      exit 0
    fi
    if wizard_run; then
      break
    fi
  done

  configure_runtime_defaults

  if ! install_wireguard; then
    printf '\n'
    tui_error "Installation did not complete. Review ${LOGFILE} before trying again."
    tui_pause
    tui_cleanup
    exit 1
  fi

  if [[ "$TUI_DRY_RUN" -eq 1 ]]; then
    tui_screen_start "Dry run complete" "No changes were made to this server."
    tui_paragraph "The wizard walked through every step and printed the commands it would run. Remove --dry-run when you are ready to install."
    tui_footer
    tui_pause
    tui_cleanup
    exit 0
  fi

  show_success
  tui_cleanup
}

main "$@"
