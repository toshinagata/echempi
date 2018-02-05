if (tty | grep '\/dev\/tty' >/dev/null); then
  if ! (ps -a | grep luajit >/dev/null); then
    cd echem; sudo luajit echem.lua
  fi
fi
