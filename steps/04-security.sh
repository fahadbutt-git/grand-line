# shellcheck shell=bash
# A security baseline, checked on every run and changed only where it is off:
# the firewall (with stealth mode, as Omarchy's firewall blocks incoming
# connections), automatic security updates, and FileVault disk encryption.

step_security() {
  local fw=/usr/libexec/ApplicationFirewall/socketfilterfw
  if [[ "$DRY_RUN" == 1 ]]; then
    run_sh "sudo $fw --setglobalstate on >/dev/null"
    run_sh "sudo $fw --setstealthmode on >/dev/null"
  fi
  local status=0
  if [[ "$DRY_RUN" == 0 ]]; then
    "$fw" --getglobalstate 2>/dev/null | grep -q "enabled" || sudo "$fw" --setglobalstate on >/dev/null
    "$fw" --getstealthmode 2>/dev/null | grep -q "on" || sudo "$fw" --setstealthmode on >/dev/null
    # Read back: a firewall managed by your organisation, or a sudo that
    # failed, leaves it as it was, and that must not pass as done.
    if ! "$fw" --getglobalstate 2>/dev/null | grep -q "enabled"; then
      warn "The firewall is still off (managed by your organisation, or sudo failed). Turn it on in System Settings, Network, Firewall."
      status=1
    elif ! "$fw" --getstealthmode 2>/dev/null | grep -q "on"; then
      warn "The firewall is on, but stealth mode is still off. Turn it on in System Settings, Network, Firewall, Options."
      status=1
    fi
  fi

  # Security fixes and system data files install by themselves.
  local su=/Library/Preferences/com.apple.SoftwareUpdate key off=""
  for key in AutomaticCheckEnabled AutomaticDownload CriticalUpdateInstall ConfigDataInstall; do
    [[ "$(defaults read "$su" "$key" 2>/dev/null)" == 1 ]] && continue
    run sudo defaults write "$su" "$key" -bool true
    [[ "$DRY_RUN" == 1 || "$(defaults read "$su" "$key" 2>/dev/null)" == 1 ]] || off="$off $key"
  done
  if [[ -n "$off" ]]; then
    warn "Automatic security updates are not fully on (still off:$off). Turn them on in System Settings, General, Software Update, Automatic updates."
    status=1
  fi

  if [[ "$DRY_RUN" == 0 ]] && ! fdesetup status 2>/dev/null | grep -q "On"; then
    warn "FileVault is off, so the disk is not encrypted. Turn it on in System Settings, Privacy and Security, FileVault."
  fi
  [[ "$status" == 0 ]] && ok "Firewall on (stealth mode), automatic security updates on"
  return "$status"
}
