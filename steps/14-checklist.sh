# shellcheck shell=bash
# Writes the list of clicks macOS insists on to Documents.
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

2. Desktops and window tiling (built into macOS)
   Add desktops in Mission Control (three-finger swipe up, then +).
   Caps + 1 to 9 switches desktop, Caps + Tab and Caps + Shift + Tab go
   to the next and previous one. macOS cannot move a window to another
   desktop by keyboard: drag it there in Mission Control, or right-click
   its Dock icon, Options, Assign To. Tiling: Caps + Left, Right, Up and
   Down fill that half, Caps + Shift + Left or Right puts this window and
   the previous one side by side, Caps + F fills the screen and Caps + R
   returns the window to its size before.

3. Maccy (clipboard history)
   Open Maccy, allow Accessibility, and in its settings turn on
   "Launch at login". Leave Spotlight's own clipboard off: it keeps
   about 10 items for 8 hours, Maccy keeps everything and searches it.
   Maccy never records what you copy in the Horizon app. It cannot tell
   a browser tab apart, so use the app, not its web version, for
   patient information.
   Universal Clipboard sends whatever you copy, Horizon included, to your
   iPhone and other Macs. To turn it off (it also turns off Handoff), in
   Terminal run:
     defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool false
     defaults -currentHost write com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool false
   or in System Settings, General, AirDrop and Handoff, turn off
   "Allow Handoff between this Mac and your iCloud devices".

4. Dictation and meetings
   Handy: open it, allow Microphone and Accessibility, let it download
   its speech model, then in its settings click the shortcut box and
   press Caps + Ctrl + X. Hold that to dictate, release to type it out.
   Leave Apple's dictation off (System Settings, Keyboard) so the two
   never listen at once.
   Meetily: open it, allow Microphone and Screen and System Audio
   Recording (that is how it hears the other side of a call), and let
   it download its model. Start it at the beginning of each meeting.

5. The notch (Iceberg)
   Hover over the notch once. Allow Calendars and Reminders when asked so
   it can show your day. Google calendars appear once they are added in
   System Settings, Internet Accounts. Add your own widgets in
   ~/.config/grand-line/iceberg/widgets/ (see apps/iceberg/README.md).

6. Sight (search)
   After the restart at the end of this list, Command + Space opens
   Sight (until then, its menu bar icon does). Allow Sight in System
   Settings, Privacy and Security, Accessibility, so it can search menus
   and paste. To go back to Spotlight: Caps + Ctrl + O, then the Sight
   toggle.

7. The file index (Grand Line Index)
   Sight searches through an index that runs in the background. If
   macOS asks, allow it in System Settings, General, Login Items, Allow
   in the Background, Grand Line Index. Then give it Full Disk Access
   (setup opens the page): System Settings, Privacy and Security, Full
   Disk Access, +, choose Grand Line Index in Applications. Without it,
   allow it Desktop, Documents, Downloads and Google Drive under Files
   and Folders instead.

8. Volume for each app (FineTune)
   Open FineTune and allow audio access when asked. Its menu bar icon
   then sets or mutes each app's volume. A browser mutes a single tab
   itself: right-click the tab, Mute Tab.

9. Downloads sorting
   The first time a file lands in Downloads, macOS asks whether
   downloads-agent may use the Downloads folder. Click Allow.

10. Notifications from the shortcuts
    In Terminal run:  osascript -e 'display notification "test"'
    Then allow Script Editor in System Settings, Notifications.

11. Google Drive
    Sign in and keep "Stream files" (the default): every file shows in
    Finder but downloads only when opened. Search finds every file by
    name. To search inside a folder's files too, right-click it in
    Finder, Google Drive, "Available offline". Then run:  update

12. Screen capture and text capture
    The first time you use the capture menu, allow Screen Recording
    for karabiner_console_user_server when macOS asks. This lets the
    package's own shortcut commands see the screen, nothing else.

13. Sign in to your apps
    Zen (to bring your Chrome bookmarks, export them on the old Mac:
    Chrome, Bookmarks, Bookmark Manager, Export; then in Zen: Bookmarks,
    Manage Bookmarks, Import), Claude, Claude Code (claude), Codex (codex), Antigravity
    (agy), ChatGPT, Gemini, Notion, Anki (AnkiWeb), WhatsApp, Zoom,
    Discord, Spotify, Plaud, Horizon and Proton VPN (free plan). Leave
    the VPN off on hospital and school networks, where it can block
    Horizon.

14. Keep start-up light
    In Spotify and Discord settings, turn off "Open at login".
    Then review System Settings, General, Login Items and turn off
    anything you do not need at start-up. An app listed there that is no
    longer installed (such as one of this package's apps under an earlier
    name) is removed with the minus button. In System Settings, Menu Bar,
    turn off the icons you do not need to see.

15. Install by hand (not available through Homebrew)
    VoiceStudio.
    Microsoft Defender, only if your school or hospital IT requires it.

16. Keep this package in sync with GitHub
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

17. Google Drive from Terminal (optional, for bulk tidying and the NAS)
    In Terminal: rclone config, choose "drive", and follow the prompts.

18. Xcode, only when you start building Mac apps
    Install it from the App Store (about 15 GB).

19. Restart the Mac once.

Everyday commands, from Terminal or the Caps Lock menu:
   update          update every app and tool
   keybindings     list every shortcut
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
    open -a "Maccy" 2>/dev/null
    open -a "Iceberg" 2>/dev/null
    # The file index needs Full Disk Access (or Files and Folders) to search.
    [[ -d "/Applications/Grand Line Index.app" ]] && open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null
  fi
  mark_done checklist
  ok "Checklist saved to Documents (it opens now)"
}
