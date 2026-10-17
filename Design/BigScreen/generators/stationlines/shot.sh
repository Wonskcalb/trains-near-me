#!/bin/sh
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for v in A B C; do
  "$C" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 \
    --window-size=2872,1300 --screenshot=/Users/valz/Documents/perso/trains-near-me/Design/BigScreen/StationLines-$v.png \
    file:///tmp/stationlines/$v.html 2>/dev/null
done
