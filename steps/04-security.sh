# shellcheck shell=bash
# A security baseline, checked on every run and changed only where it is off:
# the firewall (with stealth mode, as Omarchy's firewall blocks incoming
# connections), automatic security updates, and FileVault disk encryption.

step_security() {
  local fw=/usr/libexec/ApplicationFirewall/socketfilterfw
  if [[ "$DRY_RUN" == 1 ]] || ! "$fw" --getglobalstate 2>/dev/null | grep -q "enabled"; then
    run_sh "sudo $fw --setglobalstate on >/dev/null"
  fi
  if [[ "$DRY_RUN" == 1 ]] || ! "$fw" --getstealthmode 2>/dev/null | grep -q "on"; then
    run_sh "sudo $fw --setstealthmode on >/dev/null"
  fi

  # Security fixes and system data files install by themselves.
  local su=/Library/Preferences/com.apple.SoftwareUpdate key
  for key in AutomaticCheckEnabled AutomaticDownload CriticalUpdateInstall ConfigDataInstall; do
    [[ "$(defaults read "$su" "$key" 2>/dev/null)" == 1 ]] || run sudo defaults write "$su" "$key" -bool true
  done

  if [[ "$DRY_RUN" == 0 ]] && ! fdesetup status 2>/dev/null | grep -q "On"; then
    warn "FileVault is off, so the disk is not encrypted. Turn it on in System Settings, Privacy and Security, FileVault."
  fi
  ok "Firewall on (stealth mode), automatic security updates on"
}
