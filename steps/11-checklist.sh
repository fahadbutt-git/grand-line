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
   "Launch at login".

4. Notifications from the shortcuts
   In Terminal run:  osascript -e 'display notification "test"'
   Then allow Script Editor in System Settings, Notifications.

5. Google Drive
   Sign in. In Drive settings, under My Drive syncing options,
   choose "Mirror files" (needed for full-text search on the Mac).

6. Screen capture and text capture
   The first time you use the capture menu, allow Screen Recording
   for karabiner_console_user_server when macOS asks.

7. Sign in to your apps
   Chrome, Claude, ChatGPT, Gemini, Notion, TickTick, WhatsApp,
   Zoom, Discord, Spotify, Zotero, Plaud, Citrix and Horizon.

8. Keep start-up light
   In Spotify and Discord settings, turn off "Open at login".
   Then review System Settings, General, Login Items and turn off
   anything you do not need at start-up.

9. Install by hand (not available through Homebrew)
   VoiceStudio.
   Microsoft Defender, only if Western or hospital IT requires it.

10. Keep this package in sync with GitHub
    In Terminal: gh auth login

11. Restart the Mac once.

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
  printf '%s\n' "$text" > "$out"
  printf '\n%s\n' "$text"
  if [[ "$CI_MODE" == 0 ]]; then
    open "$out" 2>/dev/null
    open -a "Karabiner-Elements" 2>/dev/null
    open -a "AeroSpace" 2>/dev/null
    open -a "Maccy" 2>/dev/null
  fi
  ok "Checklist saved to your Desktop"
}
