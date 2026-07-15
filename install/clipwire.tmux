# clipwire — paste a remote clipboard image into the current pane.
#
# prefix + P fetches the image from the laptop (through the SSH reverse tunnel),
# saves it to a temp file on this host, and types the file path into the focused
# pane so your CLI agent can read it. Adjust the key to taste.
bind-key P run-shell 'p=$(clipwire pull 2>/dev/null) && tmux send-keys -t "#{pane_id}" " $p "'
