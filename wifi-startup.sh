#!/bin/bash

# 1. Ensure the drivers are loaded
# Even if they are already loaded, modprobe won't hurt.
sudo modprobe aic8800_fdrv 2>/dev/null
sleep 2

# 2. This resets the state machine for the AIC8800 chip
nmcli radio wifi off
sleep 2
nmcli radio wifi on
sleep 5

# 3. Force the scan and connect
# Note: Ensure "Wireless" or your SSID matches exactly
nmcli device wifi rescan
sleep 5

# 4. Connect
nmcli dev wifi connect "CHANGEME" password "CHANGEMEALSO"
