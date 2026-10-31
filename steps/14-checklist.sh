# shellcheck shell=bash
# Writes the list of clicks macOS insists on to Documents (the Desktop stays empty).
# App names here are plain text: keep them in step with the Brewfile by hand.

step_checklist() {
  local out="$HOME/Documents/Finish setup.txt" text
  # read, not $(cat <<EOF): macOS's bash 3.2 misreads apostrophes inside $( ).
  IFS= read -r -d '' text <<'EOF' || true
Finish setup

macOS requires these clicks from you. Work down the list once.

1. Karabiner-Elements (Caps Lock layer)
   Open Karabiner-Elements. Allow its driver in System Settings,
   General, Login Items and Extensions, then allow Input Monitoring
   for karabiner_grabber and karabiner_observer when asked.

2. AeroSpace (window tiling) and the drop-down terminal
   Open AeroSpace and allow Accessibility when asked. Then press
   Caps + ` once and allow Ghostty under Accessibility too, so its
   quick terminal can drop down over any app.

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

6. The notch (Den Den)
   Hover over the notch once. Allow Calendars and Reminders when asked so
   it can show your day. Google calendars appear once they are added in
   System Settings, Internet Accounts. Add your own widgets in
   ~/.config/grand-line/denden/widgets/ (see apps/denden/README.md).

7. Volume for each app (FineTune)
   Open FineTune and allow audio access when asked. Its menu bar icon
   then sets or mutes each app's volume. Chrome mutes a single tab
   itself: right-click the tab, Mute site.

8. The desktop as a dashboard
   The desktop shows no files, only widgets. First add Google Calendar
   to the Mac: System Settings, Internet Accounts, Add Account, Google,
   then turn on Calendars. Then right-click the desktop, Edit Widgets,
   and drag on Calendar (Up Next or List), Reminders and Weather.
   In System Settings, Desktop and Dock, set Widget style to
   Monochrome so they take the theme's colours. Workspace 8 is kept
   empty, so Caps + 8 always shows the dashboard.

9. Downloads sorting
   The first time a file lands in Downloads, macOS asks whether
   downloads-agent may use the Downloads folder. Click Allow.

10. Notifications from the shortcuts
    In Terminal run:  osascript -e 'display notification "test"'
    Then allow Script Editor in System Settings, Notifications.

11. Google Drive
    Sign in. In Drive settings, under My Drive syncing options,
    choose "Mirror files" (needed for full-text search on the Mac).

12. Screen capture and text capture
    The first time you use the capture menu, allow Screen Recording
    for karabiner_console_user_server when macOS asks. This lets the
    package's own shortcut commands see the screen, nothing else.

13. Sign in to your apps
    Chrome, Claude, Claude Code (claude), Codex (codex), Antigravity
    (agy), ChatGPT, Gemini, Notion, Anki (AnkiWeb), WhatsApp, Zoom,
    Discord, Spotify, Plaud, Citrix, Horizon, Proton VPN (free
    plan) and Tailscale. Leave the VPN off on hospital and school networks, where it
    can block Citrix and Horizon. Run one VPN at a time: turn Proton
    off while using Tailscale to reach the homelab.

14. Keep start-up light
    In Spotify and Discord settings, turn off "Open at login".
    Then review System Settings, General, Login Items and turn off
    anything you do not need at start-up. In System Settings, Menu Bar,
    turn off the icons you do not need to see.

15. Install by hand (not available through Homebrew)
    VoiceStudio.
    Microsoft Defender, only if Western or hospital IT requires it.

16. Keep this package in sync with GitHub
    In Terminal: gh auth login

17. Google Drive from Terminal (optional, for bulk tidying and the NAS)
    In Terminal: rclone config, choose "drive", and follow the prompts.

18. Xcode, only when you start building Mac apps
    Install it from the App Store (about 15 GB).

19. Restart the Mac once.

Everyday commands, from Terminal or the Caps Lock menu:
   update          update every app and tool
   keybindings     list every shortcut
   theme pick      change theme and background
EOF
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
  ok "Checklist saved to Documents (it opens now)"
}
