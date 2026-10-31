# shellcheck shell=bash
# Writes the list of clicks macOS insists on to the Desktop.
# App names here are plain text: keep them in step with the Brewfile by hand.

step_checklist() {
  local out="$HOME/Desktop/Finish setup.txt" text
  text="$(cat <<'EOF'
Finish setup

macOS requires these clicks from you. Work down the list once.

1. Karabiner-Elements (Caps Lock layer)
   Open Karabiner-Elements. Allow its driver in System Settings,
   General, Login Items and Extensions, then allow Input Monitoring
   for karabiner_grabber and karabiner_observer when asked.

2. AeroSpace (window tiling)
   Open AeroSpace and allow Accessibility when asked.

3. Maccy (clipboard history)
   Open Maccy, allow Accessibility, and in its settings turn on
   "Launch at login". Leave Spotlight's own clipboard off: it keeps
   about 10 items for 8 hours, Maccy keeps everything and searches it.

4. Espanso (text shortcuts such as ;date and ;sig)
   Open Espanso and allow Accessibility when asked.

5. Dictation and meetings
   Handy: open it, allow Microphone and Accessibility, let it download
   its speech model, then in its settings click the shortcut box and
   press Caps + Ctrl + X. Hold that to dictate, release to type it out.
   Leave Apple's dictation off (System Settings, Keyboard) so the two
   never listen at once.
   Meetily: open it, allow Microphone and Screen and System Audio
   Recording (that is how it hears the other side of a call), and let
   it download its model. Start it at the beginning of each meeting.

6. Downloads sorting
   The first time a file lands in Downloads, macOS asks whether
   downloads-agent may use the Downloads folder. Click Allow.

7. Notifications from the shortcuts
   In Terminal run:  osascript -e 'display notification "test"'
   Then allow Script Editor in System Settings, Notifications.

8. Google Drive
   Sign in. In Drive settings, under My Drive syncing options,
   choose "Mirror files" (needed for full-text search on the Mac).

9. Screen capture and text capture
   The first time you use the capture menu, allow Screen Recording
   for karabiner_console_user_server when macOS asks. This lets the
   package's own shortcut commands see the screen, nothing else.

10. Sign in to your apps
    Chrome, Claude, Claude Code (claude), Codex (codex), Antigravity
    (agy), ChatGPT, Gemini, Notion, Anki (AnkiWeb), WhatsApp, Zoom,
    Discord, Spotify, Plaud, Citrix, Horizon, Proton VPN (free
    plan) and Tailscale. Leave the VPN off on hospital and school networks, where it
    can block Citrix and Horizon. Run one VPN at a time: turn Proton
    off while using Tailscale to reach the homelab.

11. Keep start-up light
    In Spotify and Discord settings, turn off "Open at login".
    Then review System Settings, General, Login Items and turn off
    anything you do not need at start-up. In System Settings, Menu Bar,
    turn off the icons you do not need to see.

12. Install by hand (not available through Homebrew)
    VoiceStudio.
    Microsoft Defender, only if Western or hospital IT requires it.

13. Keep this package in sync with GitHub
    In Terminal: gh auth login

14. Google Drive from Terminal (optional, for bulk tidying and the NAS)
    In Terminal: rclone config, choose "drive", and follow the prompts.

15. Xcode, only when you start building Mac apps
    Install it from the App Store (about 15 GB).

16. Restart the Mac once.

Everyday commands, from Terminal or the Caps Lock menu:
   update          update every app and tool
   keybindings     list every shortcut
   theme pick      change theme and background
EOF
)"
  if [[ "$DRY_RUN" == 1 ]]; then
    run "write the finishing checklist to $out"
    return 0
  fi
  if ! first_time checklist; then
    return 0
  fi
  printf '%s\n' "$text" > "$out"
  printf '\n%s\n' "$text"
  if [[ "$CI_MODE" == 0 ]]; then
    open "$out" 2>/dev/null
    open -a "Karabiner-Elements" 2>/dev/null
    open -a "AeroSpace" 2>/dev/null
    open -a "Maccy" 2>/dev/null
    open -a "Espanso" 2>/dev/null
  fi
  mark_done checklist
  ok "Checklist saved to your Desktop"
}
