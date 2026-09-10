#!/bin/sh
# Answers what ssh and git would ask on a terminal, since the app runs them without one:
# a hidden-answer dialog for passphrases and passwords, a Yes/No dialog for host confirmations.
prompt="$1"
case "$prompt" in
  *"(yes/no"*)
    osascript \
      -e 'on run argv' \
      -e 'display dialog (item 1 of argv) with title "Lanes" buttons {"No", "Yes"} default button "Yes" with icon caution' \
      -e 'if button returned of result is "Yes" then return "yes"' \
      -e 'return "no"' \
      -e 'end run' "$prompt"
    ;;
  *)
    osascript \
      -e 'on run argv' \
      -e 'display dialog (item 1 of argv) with title "Lanes" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK"' \
      -e 'return text returned of result' \
      -e 'end run' "$prompt"
    ;;
esac
