# Written by: theme set {{ NAME }}. Linked as lazygit's config.yml only when
# you had none. To keep your own settings, replace the link with a file.
gui:
  nerdFontsVersion: "3"
  theme:
    activeBorderColor: ["#{{ ACCENT_HEX }}", bold]
    inactiveBorderColor: ["#{{ MUTED }}"]
    searchingActiveBorderColor: ["#{{ HIGHLIGHT }}", bold]
    optionsTextColor: ["#{{ HIGHLIGHT }}"]
    selectedLineBgColor: ["#{{ TERM_SELECTION }}"]
    inactiveViewSelectedLineBgColor: ["#{{ BG_LIGHTER }}"]
    cherryPickedCommitFgColor: ["#{{ ACCENT_HEX }}"]
    cherryPickedCommitBgColor: ["#{{ TERM_SELECTION }}"]
    markedBaseCommitFgColor: ["#{{ COLOR3 }}"]
    markedBaseCommitBgColor: ["#{{ TERM_SELECTION }}"]
    unstagedChangesColor: ["#{{ COLOR1 }}"]
    defaultFgColor: ["#{{ TERM_FG }}"]
