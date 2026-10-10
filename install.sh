#!/usr/bin/env bash
# install omarchy-custom SDDM theme and enable it.
# Repo: https://github.com/nightdevil00/omarchy-custom
# Usage (from a git clone):
#   git clone https://github.com/nightdevil00/omarchy-custom.git
#   cd omarchy-custom
#   ./install.sh [options]
#
# Theme options:
#   --dry-run            print what would be done, change nothing
#   --no-enable          copy files but don't select the theme
#   --keep-autologin     don't remove /etc/sddm.conf.d/autologin.conf
#   --skip-lint          don't run qmllint (it segfaults on some files)
#
# User options (so one call does everything):
#   --add-user <name>    create the user (or update groups if it exists)
#                        and set its password via passwd
#   --groups <g1,g2>     supplementary groups (default: none; wheel = admin)
#   --sudo               grant sudo with password (/etc/sudoers.d/<name>)
#   --sudo-nopasswd      grant passwordless sudo (less secure than --sudo)
#   --skip-password      don't touch the password (groups/sudo only)
#   -h, --help           this help
#
# Example (theme + user + sudo in one go):
#   ./install.sh --add-user alice --groups wheel --sudo
#
# Works regardless of where the repo is cloned: theme sources are resolved
# relative to this script (repo root) with fallback to ./omarchy-custom/
# for checkouts where the theme lives in a subdirectory.
set -euo pipefail
IFS=$'\n\t'

readonly PROG=${0##*/}
readonly THEME="omarchy-custom"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Theme sources: repo root (git clone layout) or ./omarchy-custom/ subdir
# (parent-checkout layout, e.g. ~/custom with omarchy-custom/ inside).
if [[ -f "$SCRIPT_DIR/Main.qml" ]]; then
  readonly SRC_DIR="$SCRIPT_DIR"
elif [[ -f "$SCRIPT_DIR/$THEME/Main.qml" ]]; then
  readonly SRC_DIR="$SCRIPT_DIR/$THEME"
else
  printf '[%s] ERROR: cannot find Main.qml in %s or %s/%s (run from git clone root)\n' \
    "${0##*/}" "$SCRIPT_DIR" "$SCRIPT_DIR" "$THEME" >&2
  exit 1
fi
readonly DEST_DIR="/usr/share/sddm/themes/${THEME}"
# Must sort AFTER 99-omarchy-login.conf (SDDM merges drop-ins lexically,
# later wins). zz- prefix guarantees that; 20- would silently lose.
readonly CONF_FILE="/etc/sddm.conf.d/zz-omarchy-custom-theme.conf"
readonly AUTOLOGIN_CONF="/etc/sddm.conf.d/autologin.conf"
# SDDM loads EVERY file in /etc/sddm.conf.d (not just *.conf), so backups
# must live outside that dir or a stale autologin.conf.bak would re-enable
# autologin. Same reason theme backups don't go next to the theme dir
# (they'd show up as phantom themes).
readonly BACKUP_ROOT="/var/backups/omarchy-custom-sddm"
readonly TS="$(date +%s)"

log() { printf '[%s] %s\n' "$PROG" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Refuse to replace a sudoers file unless it is exactly one rule written by
# this installer or the user-admin tools. A matching line alone is not enough.
managed_sudoers_file() {
  local file=$1 user=$2 rule
  sudo test -f "$file" && ! sudo test -L "$file" || return 1
  for rule in "$user ALL=(ALL) ALL" "$user ALL=(ALL) NOPASSWD: ALL"; do
    if sudo cat -- "$file" | cmp -s - <(printf '%s\n' "$rule"); then
      return 0
    fi
  done
  return 1
}

DRY_RUN=0
ENABLE=1
KEEP_AUTOLOGIN=0
ADD_USER=""
USER_GROUPS=""
GROUPS_GIVEN=0
GRANT_SUDO=0
GRANT_SUDO_NOPASSWD=0
SKIP_PASSWORD=0
SKIP_LINT=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=1; shift ;;
    --no-enable) ENABLE=0; shift ;;
    --keep-autologin) KEEP_AUTOLOGIN=1; shift ;;
    --skip-lint) SKIP_LINT=1; shift ;;
    --add-user)
      [[ $# -ge 2 ]] || die "--add-user needs a username argument"
      ADD_USER="$2"; shift 2 ;;
    --groups)
      [[ $# -ge 2 ]] || die "--groups needs a comma-separated list argument"
      USER_GROUPS="$2"; GROUPS_GIVEN=1; shift 2 ;;
    --sudo) GRANT_SUDO=1; shift ;;
    --sudo-nopasswd) GRANT_SUDO_NOPASSWD=1; shift ;;
    --skip-password) SKIP_PASSWORD=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown flag: $1" ;;
    *) break ;;
  esac
done

if [[ $GRANT_SUDO -eq 1 && $GRANT_SUDO_NOPASSWD -eq 1 ]]; then
  die "--sudo and --sudo-nopasswd are mutually exclusive"
fi
if [[ -z "$ADD_USER" && ( $GROUPS_GIVEN -eq 1 || $GRANT_SUDO -eq 1 || $GRANT_SUDO_NOPASSWD -eq 1 || $SKIP_PASSWORD -eq 1 ) ]]; then
  die "--groups/--sudo/--sudo-nopasswd/--skip-password need --add-user <name>"
fi
if [[ -n "$ADD_USER" ]] && ! [[ "$ADD_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  die "invalid username: $ADD_USER (use lowercase letters, digits, _ or -)"
fi
if [[ -n "$ADD_USER" ]]; then
  # Validate requested groups before touching the system. An empty list is
  # fine: a plain user needs no supplementary groups, and wheel makes the
  # user a polkit administrator (root via pkexec/run0 with their own password).
  IFS=',' read -ra GROUP_ARR <<< "$USER_GROUPS"
  for g in ${GROUP_ARR[@]+"${GROUP_ARR[@]}"}; do
    [[ -n "$g" ]] || die "empty group name in --groups '$USER_GROUPS'"
    getent group "$g" >/dev/null || die "unknown group: $g (check with 'getent group <name>')"
  done
fi

# Check before changing the theme or account so an unrelated sudoers file
# cannot turn a combined install into a partial update.
if [[ -n "$ADD_USER" ]]; then
  sudoers_file="/etc/sudoers.d/$ADD_USER"
  if sudo test -e "$sudoers_file" || sudo test -L "$sudoers_file"; then
    if ! id "$ADD_USER" &>/dev/null; then
      die "$sudoers_file already exists and would apply to the new account. Inspect it with 'sudo visudo -f $sudoers_file' and remove it before creating $ADD_USER"
    fi
    if (( GRANT_SUDO || GRANT_SUDO_NOPASSWD )); then
      managed_sudoers_file "$sudoers_file" "$ADD_USER" ||
        die "$sudoers_file is not exactly one managed rule for $ADD_USER. Inspect it with 'sudo visudo -f $sudoers_file'; omit --sudo/--sudo-nopasswd to install without changing sudo"
    fi
  fi
fi

for f in Main.qml metadata.desktop theme.conf; do
  [[ -f "$SRC_DIR/$f" ]] || die "missing source file: $SRC_DIR/$f"
done

if [[ $SKIP_LINT -eq 1 ]]; then
  log "skipping QML lint (--skip-lint)"
elif command -v qmllint >/dev/null 2>&1; then
  if ! qmllint "$SRC_DIR/Main.qml"; then
    die "qmllint failed on Main.qml (retry with --skip-lint if qmllint itself crashed)"
  fi
else
  log "qmllint not found, skipping QML lint"
fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n' >&2
  else
    "$@"
  fi
}

log "installing $THEME -> $DEST_DIR"
run sudo mkdir -p -- "$DEST_DIR" "$BACKUP_ROOT"

if sudo test -e "$DEST_DIR/Main.qml"; then
  backup="$BACKUP_ROOT/${THEME}.bak.$TS"
  log "backing up existing theme to $backup"
  run sudo cp -a -- "$DEST_DIR" "$backup"
fi

# install (not cp -a): don't carry the checkout's owner, mode or symlinks
# into a root-owned directory.
run sudo install -m 0644 -o root -g root -- "$SRC_DIR/Main.qml" "$SRC_DIR/metadata.desktop" "$SRC_DIR/theme.conf" "$DEST_DIR/"
for img in bullet.png entry.png entry-failed.png lock.png lock-failed.png logo.png; do
  if [[ -f "$SRC_DIR/$img" ]]; then
    run sudo install -m 0644 -o root -g root -- "$SRC_DIR/$img" "$DEST_DIR/"
  fi
done
run sudo chmod 755 -- "$DEST_DIR"
run sudo chmod 644 -- "$DEST_DIR/Main.qml" "$DEST_DIR/metadata.desktop" "$DEST_DIR/theme.conf"
run sudo chown -R root:root -- "$DEST_DIR"

if [[ $ENABLE -eq 1 ]]; then
  log "enabling theme in $CONF_FILE"
  if sudo test -f "$CONF_FILE"; then
    run sudo cp -a -- "$CONF_FILE" "$BACKUP_ROOT/zz-omarchy-custom-theme.conf.bak.$TS"
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '+ sudo tee %s (contents: [Theme] Current=%s)\n' "$CONF_FILE" "$THEME" >&2
  else
    printf '[Theme]\nCurrent=%s\n' "$THEME" | sudo tee "$CONF_FILE" >/dev/null
  fi
fi

log "verifying"
run ls -l -- "$DEST_DIR"
if [[ $ENABLE -eq 1 ]]; then
  run cat -- "$CONF_FILE"
fi

if [[ $KEEP_AUTOLOGIN -eq 0 ]]; then
  if sudo test -f "$AUTOLOGIN_CONF"; then
    backup_autologin="$BACKUP_ROOT/autologin.conf.bak.$TS"
    log "autologin found, disabling: backup to $backup_autologin then remove $AUTOLOGIN_CONF"
    run sudo cp -a -- "$AUTOLOGIN_CONF" "$backup_autologin"
    run sudo rm -f -- "$AUTOLOGIN_CONF"
  else
    log "no autologin file at $AUTOLOGIN_CONF, nothing to disable"
  fi
else
  log "keeping autologin (--keep-autologin), greeter will still be bypassed on boot"
fi

if [[ -n "$ADD_USER" ]]; then
  if [[ -x /usr/bin/bash ]]; then
    USER_SHELL=/usr/bin/bash
  else
    USER_SHELL=/bin/bash
  fi
  # Groups were validated upfront; just create/update here.
  if id "$ADD_USER" &>/dev/null; then
    log "user $ADD_USER exists, adding groups: ${USER_GROUPS:-<none>}"
  else
    log "creating user $ADD_USER (shell $USER_SHELL, groups ${USER_GROUPS:-<none>})"
    run sudo useradd -m -s "$USER_SHELL" "$ADD_USER"
  fi
  if [[ -n "$USER_GROUPS" ]]; then
    run sudo usermod -aG "$USER_GROUPS" "$ADD_USER"
  fi
  if [[ ",$USER_GROUPS," == *,wheel,* ]]; then
    log "note: wheel makes $ADD_USER an administrator (root via pkexec/run0 with their own password)"
  fi

  if [[ $SKIP_PASSWORD -eq 1 ]]; then
    log "skipping password for $ADD_USER (--skip-password)"
  elif [[ $DRY_RUN -eq 1 ]]; then
    printf '+ sudo passwd %s (interactive password prompt)\n' "$ADD_USER" >&2
  else
    log "set password for $ADD_USER"
    sudo passwd "$ADD_USER"
  fi

  if [[ $GRANT_SUDO -eq 1 || $GRANT_SUDO_NOPASSWD -eq 1 ]]; then
    sudoers_file="/etc/sudoers.d/$ADD_USER"
    if sudo test -e "$sudoers_file" || sudo test -L "$sudoers_file"; then
      managed_sudoers_file "$sudoers_file" "$ADD_USER" ||
        die "$sudoers_file changed or is not managed. Inspect it with 'sudo visudo -f $sudoers_file' before retrying"
    fi
    if [[ $GRANT_SUDO_NOPASSWD -eq 1 ]]; then
      sudoers_line="$ADD_USER ALL=(ALL) NOPASSWD: ALL"
    else
      sudoers_line="$ADD_USER ALL=(ALL) ALL"
    fi
    log "granting sudo to $ADD_USER via $sudoers_file"
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '+ visudo -cf <tmp with %s> && sudo install -m 0440 -o root -g root <tmp> %s && sudo visudo -c\n' \
        "'$sudoers_line'" "$sudoers_file" >&2
    else
      # Validate before installing: a broken drop-in in /etc/sudoers.d
      # can take sudo down for everyone.
      sudoers_tmp="$(mktemp)"
      printf '%s\n' "$sudoers_line" >"$sudoers_tmp"
      if ! sudo visudo -cf "$sudoers_tmp" >/dev/null; then
        rm -f -- "$sudoers_tmp"
        die "generated sudoers rule failed validation, nothing written"
      fi
      sudo install -m 0440 -o root -g root -- "$sudoers_tmp" "$sudoers_file"
      rm -f -- "$sudoers_tmp"
      sudo visudo -c
    fi
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "dry-run: would create/update user $ADD_USER (groups ${USER_GROUPS:-<none>})"
  else
    log "user $ADD_USER ready: $(id "$ADD_USER")"
  fi
  log "first graphical login provisions the desktop (or run 'omarchy-provision-user' as $ADD_USER)"
fi

log "done. Takes effect on next SDDM greeter (logout/reboot)."
log "To test now (logs you out): sudo systemctl restart sddm"
