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
   Maccy never records what you copy in the Citrix and Horizon apps. It
   cannot tell a browser tab apart, so use those apps, not their web
   versions, for patient information.
   Universal Clipboard sends whatever you copy, Citrix included, to your
   iPhone and other Macs. To turn it off (it also turns off Handoff), in
   Terminal run:
     defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool false
     defaults -currentHost write com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool false
   or in System Settings, General, AirDrop and Handoff, turn off
   "Allow Handoff between this Mac and your iCloud devices".

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

6. The notch (Iceberg)
   Hover over the notch once. Allow Calendars and Reminders when asked so
   it can show your day. Google calendars appear once they are added in
   System Settings, Internet Accounts. Add your own widgets in
   ~/.config/grand-line/iceberg/widgets/ (see apps/iceberg/README.md).

7. Sight and Nexus (search and files)
   After the restart at the end of this list, Command + Space opens
   Sight (until then, its menu bar icon does). Allow Sight in System Settings, Privacy and
   Security, Accessibility, so it can search menus and paste. Folders and
   "Show in Finder" now open in Nexus; the first Empty Trash asks to
   let it tell Finder. To go back to Spotlight or Finder: Caps + Ctrl + O,
   then the Sight or Nexus toggle.

8. The file index (Grand Line Index)
   Sight and Nexus search through one shared index that runs in the
   background. If macOS asks, allow it in System Settings, General, Login
   Items, Allow in the Background, Grand Line Index. Then give it Full
   Disk Access (setup opens the page): System Settings, Privacy and
   Security, Full Disk Access, +, choose Grand Line Index in
   Applications. Without it, allow it Desktop, Documents, Downloads and
   Google Drive under Files and Folders instead. Nexus asks for Files and
   Folders itself when it browses there; Sight no longer needs it.

9. Volume for each app (FineTune)
   Open FineTune and allow audio access when asked. Its menu bar icon
   then sets or mutes each app's volume. A browser mutes a single tab
   itself: right-click the tab, Mute Tab.

10. The desktop as a dashboard
   The desktop shows no files, only widgets. First add Google Calendar
   to the Mac: System Settings, Internet Accounts, Add Account, Google,
   then turn on Calendars. Then right-click the desktop, Edit Widgets,
   and drag on Calendar (Up Next or List), Reminders and Weather.
   In System Settings, Desktop and Dock, set Widget style to
   Monochrome so they take the theme's colours. Workspace 8 is kept
   empty, so Caps + 8 always shows the dashboard.

11. Downloads sorting
   The first time a file lands in Downloads, macOS asks whether
   downloads-agent may use the Downloads folder. Click Allow.

12. Notifications from the shortcuts
    In Terminal run:  osascript -e 'display notification "test"'
    Then allow Script Editor in System Settings, Notifications.

13. Google Drive
    Sign in. In Drive settings, under My Drive syncing options,
    choose "Mirror files" (needed for full-text search on the Mac).

14. Screen capture and text capture
    The first time you use the capture menu, allow Screen Recording
    for karabiner_console_user_server when macOS asks. This lets the
    package's own shortcut commands see the screen, nothing else.

15. Sign in to your apps
    Zen (to bring your Chrome bookmarks, export them on the old Mac:
    Chrome, Bookmarks, Bookmark Manager, Export; then in Zen: Bookmarks,
    Manage Bookmarks, Import), Claude, Claude Code (claude), Codex (codex), Antigravity
    (agy), ChatGPT, Gemini, Notion, Anki (AnkiWeb), WhatsApp, Zoom,
    Discord, Spotify, Plaud, Citrix, Horizon, Proton VPN (free
    plan) and Tailscale. Leave the VPN off on hospital and school networks, where it
    can block Citrix and Horizon. Run one VPN at a time: turn Proton
    off while using Tailscale to reach the homelab.

16. Keep start-up light
    In Spotify and Discord settings, turn off "Open at login".
    Then review System Settings, General, Login Items and turn off
    anything you do not need at start-up. An app listed there that is no
    longer installed (such as one of this package's apps under an earlier
    name) is removed with the minus button. In System Settings, Menu Bar,
    turn off the icons you do not need to see.

17. Install by hand (not available through Homebrew)
    VoiceStudio.
    Microsoft Defender, only if your school or hospital IT requires it.

18. Keep this package in sync with GitHub
    In Terminal: gh auth login
    Updates from GitHub apply by themselves only when each commit is
    signed by a key in ~/.config/grand-line/allowed_signers (made from
    your git signing key). To sign your commits with your SSH key:
      git config --global gpg.format ssh
      git config --global user.signingkey ~/.ssh/id_ed25519.pub
      git config --global commit.gpgsign true
    then run: bash ~/grand-line/setup.sh --only auto-update
    Unsigned changes wait until you run update, which shows them and asks.
    Your own changes go to GitHub only with: grandline publish
    The package's apps are signed with a certificate made on this Mac,
    so they keep Accessibility, Calendars and Automation across updates.
    The first time they are signed this way, allow them once more.

19. Google Drive from Terminal (optional, for bulk tidying and the NAS)
    In Terminal: rclone config, choose "drive", and follow the prompts.

20. Xcode, only when you start building Mac apps
    Install it from the App Store (about 15 GB).

21. Restart the Mac once.

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
    open -a "Iceberg" 2>/dev/null
    # The file index needs Full Disk Access (or Files and Folders) to search.
    [[ -d "/Applications/Grand Line Index.app" ]] && open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null
  fi
  mark_done checklist
  ok "Checklist saved to Documents (it opens now)"
}
