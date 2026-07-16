# clipwire — paste a remote clipboard image into the current pane.
#
# Install on the machine where tmux runs (the paste TARGET). prefix + C-v pulls the
# image from the laptop through the SSH reverse tunnel, saves it, and types the file
# path into the focused pane so your CLI agent (e.g. Claude Code) can read it.
# Adjust the key to taste — plain `P` is commonly already bound (e.g. choose-buffer).
#
# PATH covers Homebrew (macOS) and `go install` (~/go/bin) locations, because tmux
# run-shell uses a non-login shell that may not have them.
bind-key C-v run-shell 'p=$(PATH="$HOME/go/bin:/opt/homebrew/bin:$PATH" clipwire pull 2>/dev/null) && tmux send-keys -t "#{pane_id}" " $p "'
