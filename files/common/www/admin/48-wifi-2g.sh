#!/bin/ash

if [ "$wifi_status_radio2g_up" = "1" ]; then
cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wifi-2g.cgi">WiFi 2.4 GHz</a></div></td></tr>
<tr><td><div class="plugin">&nbsp;&nbsp;<a class="plugin" href="splash.cgi">Splash</a></div></td></tr>
EOM
fi

