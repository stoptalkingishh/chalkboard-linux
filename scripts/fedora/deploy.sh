#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CHILD_USER="chalkboard"
VIVALDI_KEY_FINGERPRINT="8D1FA52AEF58A09D889DD4221256C34716BD9233"

require_root
require_fedora
[[ $# -eq 0 ]] || die "deploy.sh does not accept arguments"
getent passwd "$CHILD_USER" >/dev/null || die "account $CHILD_USER does not exist"
[[ "$(id -u "$CHILD_USER")" -ge 1000 ]] || die "refusing to configure a system account"
if id -nG "$CHILD_USER" | tr ' ' '\n' | grep -Eq '^(wheel|sudo)$'; then
  die "account $CHILD_USER is still an administrator"
fi

CHILD_HOME="$(child_home "$CHILD_USER")"
[[ -d "$CHILD_HOME" ]] || die "child home directory does not exist"
install -d -o root -g root -m 0700 "$STATE_DIR" "$BACKUP_DIR"
printf '%s\n' "$CHILD_USER" >"$STATE_DIR/child-user"

log "installing Fedora applications"
dnf -y install \
  bluedevil cage curl flatpak gnupg2 kdialog plasma-nm plasma-pa \
  plasma-systemsettings qt6-qttools \
  gcompris-qt kolourpaint kcalc libreoffice-writer ktuberling kmines

log "configuring the authenticated Vivaldi repository"
key_file="$(mktemp)"
trap 'rm -f "$key_file"' EXIT
curl --proto '=https' --tlsv1.2 --fail --location \
  --output "$key_file" https://repo.vivaldi.com/archive/linux_signing_key.pub
fingerprint="$(gpg --batch --with-colons --show-keys "$key_file" | awk -F: '$1 == "fpr" { print $10; exit }')"
[[ "$fingerprint" == "$VIVALDI_KEY_FINGERPRINT" ]] || die "unexpected Vivaldi signing key fingerprint: $fingerprint"
rpmkeys --import "$key_file"
install_managed_file "$REPO_ROOT/config/fedora/vivaldi.repo" /etc/yum.repos.d/vivaldi.repo
dnf -y --refresh install vivaldi-stable

log "installing CuteMaze from Flathub"
flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --system --noninteractive -y flathub org.gottcode.CuteMaze

log "backing up NetworkManager profiles"
backup_file /etc/NetworkManager/system-connections

log "configuring Cloudflare Family DNS"
install_managed_file "$REPO_ROOT/config/fedora/systemd-resolved.conf" \
  /etc/systemd/resolved.conf.d/60-chalkboard-family.conf
install_managed_file "$SCRIPT_DIR/apply-family-dns.sh" \
  /usr/local/sbin/chalkboard-family-dns 0755
install_managed_file "$REPO_ROOT/config/fedora/network-dispatcher.sh" \
  /etc/NetworkManager/dispatcher.d/90-chalkboard-family-dns 0755
bash "$SCRIPT_DIR/apply-family-dns.sh"

log "configuring power and automatic login"
install_managed_file "$REPO_ROOT/config/fedora/logind.conf" \
  /etc/systemd/logind.conf.d/90-chalkboard-power.conf
install_managed_file "$REPO_ROOT/config/fedora/sleep.conf" \
  /etc/systemd/sleep.conf.d/90-chalkboard-disable-sleep.conf
install_managed_file "$REPO_ROOT/config/fedora/sddm.conf" \
  /etc/sddm.conf.d/90-chalkboard-autologin.conf
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

log "installing Vivaldi policy"
install_managed_file "$REPO_ROOT/config/fedora/vivaldi-policy.json" \
  /etc/opt/vivaldi/policies/managed/chalkboard.json

log "preparing the child desktop"
for path in \
  "$CHILD_HOME/.config/powerdevilrc" \
  "$CHILD_HOME/.config/kscreenlockerrc" \
  "$CHILD_HOME/.config/kwalletrc" \
  "$CHILD_HOME/.config/kwinrc" \
  "$CHILD_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" \
  "$CHILD_HOME/.config/plasmashellrc" \
  "$CHILD_HOME/.config/autostart/chalkboard-first-login.desktop" \
  "$CHILD_HOME/.local/state/chalkboard/plasma-provisioned"; do
  backup_file "$path"
done
for desktop_file in "$REPO_ROOT"/config/fedora/launchers/*.desktop; do
  backup_file "$CHILD_HOME/.local/share/applications/$(basename "$desktop_file")"
done

install -d -o "$CHILD_USER" -g "$CHILD_USER" -m 0700 \
  "$CHILD_HOME/.config" \
  "$CHILD_HOME/.config/autostart" \
  "$CHILD_HOME/.local/share/applications" \
  "$CHILD_HOME/.local/state/chalkboard"

install -o "$CHILD_USER" -g "$CHILD_USER" -m 0600 \
  "$REPO_ROOT/config/fedora/powerdevilrc" "$CHILD_HOME/.config/powerdevilrc"
install -o "$CHILD_USER" -g "$CHILD_USER" -m 0600 \
  "$REPO_ROOT/config/fedora/kscreenlockerrc" "$CHILD_HOME/.config/kscreenlockerrc"
install -o "$CHILD_USER" -g "$CHILD_USER" -m 0600 \
  "$REPO_ROOT/config/fedora/kwalletrc" "$CHILD_HOME/.config/kwalletrc"
install -o "$CHILD_USER" -g "$CHILD_USER" -m 0644 \
  "$REPO_ROOT/config/fedora/first-login.desktop" \
  "$CHILD_HOME/.config/autostart/chalkboard-first-login.desktop"

for desktop_file in "$REPO_ROOT"/config/fedora/launchers/*.desktop; do
  install -o "$CHILD_USER" -g "$CHILD_USER" -m 0644 "$desktop_file" \
    "$CHILD_HOME/.local/share/applications/$(basename "$desktop_file")"
done

install_managed_file "$SCRIPT_DIR/first-login.sh" \
  /usr/local/libexec/chalkboard-first-login 0755
install_managed_file "$SCRIPT_DIR/power-menu.sh" \
  /usr/local/libexec/chalkboard-power-menu 0755
install_managed_file "$REPO_ROOT/config/fedora/kde/panel.js" \
  /usr/local/share/chalkboard/panel.js

install_managed_file "$REPO_ROOT/config/fedora/kde-session-env.sh" \
  /etc/xdg/plasma-workspace/env/10-chalkboard-kiosk.sh 0755
install_managed_file "$REPO_ROOT/config/fedora/kde/kdeglobals" \
  /usr/local/share/chalkboard/policy/kdeglobals
install_managed_file "$REPO_ROOT/config/fedora/kde/kglobalshortcutsrc" \
  /usr/local/share/chalkboard/policy/kglobalshortcutsrc

log "installing the disabled-by-default GCompris session"
backup_file /etc/sddm.conf.d/95-chalkboard-gcompris.conf
install_managed_file "$REPO_ROOT/config/fedora/gcompris-session.desktop" \
  /usr/local/share/wayland-sessions/chalkboard-gcompris.desktop
install_managed_file "$REPO_ROOT/config/fedora/gcompris-sddm.conf" \
  /usr/local/share/chalkboard/gcompris-sddm.conf
install_managed_file "$SCRIPT_DIR/gcompris-session.sh" \
  /usr/local/libexec/chalkboard-gcompris-session 0755
install_managed_file "$SCRIPT_DIR/gcompris-mode.sh" \
  /usr/local/sbin/chalkboard-gcompris-mode 0755

# install -d applies ownership to named leaf directories but not every parent it
# creates. This dedicated account must own its complete home hierarchy.
chown -R "$CHILD_USER:$CHILD_USER" "$CHILD_HOME"

restorecon -RF /etc/sddm.conf.d /etc/systemd/logind.conf.d \
  /etc/systemd/sleep.conf.d /etc/NetworkManager/dispatcher.d \
  /etc/opt/vivaldi /etc/xdg/plasma-workspace /usr/local/share/wayland-sessions \
  "$CHILD_HOME/.config" \
  "$CHILD_HOME/.local" 2>/dev/null || true

touch "$STATE_DIR/deployed"
log "stage one complete"
log "reboot to provision Plasma, then run finalize-lockdown.sh"
