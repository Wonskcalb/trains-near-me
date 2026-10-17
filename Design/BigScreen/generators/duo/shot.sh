#!/bin/sh
# usage: shot.sh page... ; renders /tmp/duo/<page>.html to Design/BigScreen/Duo/Duo-<page>.png at 2x
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT=/Users/valz/Documents/perso/trains-near-me/Design/BigScreen/Duo
for p in "$@"; do
  info=$("$C" --headless=new --disable-gpu --allow-file-access-from-files --window-size=5000,2000 --virtual-time-budget=3000 --dump-dom "file:///tmp/duo/$p.html" 2>/dev/null | grep -o 'crease-check[^>]*>SIZE [^<]*' | sed 's/.*>//')
  echo "$p: $info"
  size=$(echo "$info" | awk '{print $2}' | tr x ,)
  "$C" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=2 --virtual-time-budget=3000 \
    --window-size=$size --screenshot="$OUT/Duo-$p.png" "file:///tmp/duo/$p.html" 2>/dev/null >/dev/null
done
