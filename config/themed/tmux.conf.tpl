# Written by: theme set {{ NAME }}. Sourced by config/tmux/tmux.conf.
set -g status-style "bg=default,fg={{ MUTED }}"
setw -g window-status-current-style "fg={{ HIGHLIGHT }},bold"
set -g pane-border-style "fg={{ BG_LIGHTER }}"
set -g pane-active-border-style "fg={{ ACCENT_HEX }}"
set -g message-style "bg={{ BG_LIGHTER }},fg={{ TERM_FG }}"
set -g mode-style "bg={{ TERM_SELECTION }},fg={{ TERM_FG }}"
