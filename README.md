# Luckfox Lyra Ultra W running pymc-Repeater

Guide for setting up a Luckfox Lyra Ultra W with an e22p wehooper4 v2 Lora hat to run pymc-repeater


## 📝 Summary of Post-Flash Fixes

After the initial flash of Ubuntu 22.04, the "out-of-the-box" experience for the Lyra has three major friction points we need to solve:

1. **Hardware Enable (The GPIO 55 "Gotcha"):** The Wi-Fi chip is connected via SDIO and is physically disabled by default. It requires manual power-up via a specific GPIO pin before the OS even sees it as a device.
2. **Driver State Machine:** The `aic8800_fdrv` driver can be finicky. It often needs a software "kick" (toggling the radio off/on) to properly initialize after the module is loaded.
3. **DHCP vs. Connection Handshake:** Standard tools like `udhcpc` often loop infinitely if the physical handshake isn't perfectly timed with the driver initialization.
4. **Persistence:** Ubuntu's standard `netplan` or `interfaces` config often fails on this board because the hardware isn't "ready" when the networking service starts.

---

## 🚀 Luckfox Lyra Wi-Fi & LoRa Setup

### Luckfox Lyra (RK3506) Ubuntu 22.04 Guide

This guide covers getting Wi-Fi stable and persistent on the Luckfox Lyra Ultra W using the **AIC8800** Wi-Fi 6 chip and setting up the **LoRa HAT**.

#### 1. Initial Wi-Fi Hardware Enable

On the Lyra, the Wi-Fi chip is tied to **GPIO 55**. If this isn't high, `wlan0` will not exist or will fail to scan.

```bash
echo 55 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio55/direction
echo 1 > /sys/class/gpio/gpio55/value

```

#### 2. Install network-manager

Standard scripts can be flaky. We recommend **NetworkManager** for its better handling of link drops.

```bash
sudo apt update
sudo apt install network-manager
sudo systemctl enable --now NetworkManager

```

#### 3. Create the Persistent Startup Script

Since the Wi-Fi hardware needs a "kick" after the kernel boots, create a startup script: `sudo nano /usr/local/bin/wifi-startup.sh`

```bash
#!/bin/bash
# 1. Force load the driver
sudo modprobe aic8800_fdrv 2>/dev/null
sleep 2

# 2. Reset radio state
nmcli radio wifi off
sleep 2
nmcli radio wifi on
sleep 5

# 3. Connect to your router
nmcli dev wifi connect "YOUR_SSID" password "YOUR_PASSWORD"

```

`sudo chmod +x /usr/local/bin/wifi-startup.sh`

#### 4. Automate with Systemd

Create a service to run this on every boot: `sudo nano /etc/systemd/system/luckfox-wifi.service`

```ini
[Unit]
Description=Luckfox Lyra WiFi Hardware Kick
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wifi-startup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target

```

*Enable it:* `sudo systemctl enable luckfox-wifi.service`

#### 5. LoRa HAT Verification

If using a LoRa HAT (e.g., SX1262), verify the SPI/UART communication via `dmesg`.

```bash
dmesg | grep spi
# You should see the SPI bus initialized for the RK3506

```

### 🐍 Phase 2: Python 3.11 & Root Environment Setup

The Luckfox Lyra image comes with Python 3.10. For `pymc-repeater`, we need to install Python 3.11 and ensure `pip` is configured specifically for the root user to handle GPIO access.

#### 1. Install Python 3.11 & Pip

```bash
# Add the deadsnakes PPA for newer Python versions
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update

# Install Python 3.11 and the required header files
sudo apt install python3.11 python3.11-dev python3.11-venv -y

# Install pip specifically for Python 3.11
curl -sS https://bootstrap.pypa.io/get-pip.py | sudo python3.11

```

#### 2. Configure Python 3.11 as Default (Optional but Recommended)

To make `python3` point to 3.11:

```bash
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 2

# Verify
python3 --version

```

#### 3. Why we run as Root

On the Lyra, GPIO and SPI permissions are not persistent for non-root users out of the box. To avoid "Permission Denied" errors when `pymc-repeater` tries to access the LoRa HAT, we install the package and run the service as root.

```bash
# Install pymc-repeater dependencies as root
sudo python3 -m pip install git+https://github.com/rightup/pyMC_Repeater.git

```

---

### 📡 Phase 3: Pymc-Repeater Service Configuration

Once installed, we need to ensure the daemon starts automatically and has high-priority access to the CPU to handle LoRa timing.

#### 1. Create the Service File

`sudo nano /etc/systemd/system/pymc-repeater.service`

```ini
[Unit]
Description=PyMC LoRa Mesh Repeater Daemon
After=network-online.target luckfox-wifi.service
Wants=network-online.target

[Service]
# Run as root to ensure GPIO/SPI access
User=root
Group=root
WorkingDirectory=/opt/pymc_repeater
ExecStart=/usr/bin/python3 -m pymc_repeater.daemon --config /etc/pymc_repeater/config.yaml

# Restart on failure
Restart=always
RestartSec=5

# Give the process high priority for radio timing
CPUSchedulingPolicy=rr
CPUSchedulingPriority=50

[Install]
WantedBy=multi-user.target

```

#### 2. Enable and Monitor

```bash
sudo systemctl daemon-reload
sudo systemctl enable pymc-repeater
sudo systemctl start pymc-repeater

# Check the live logs to verify radio initialization
sudo journalctl -u pymc-repeater -f

```

---

### 🛠️ Troubleshooting GPIO Access

If you still see "Export failed" in the logs:

1. Ensure no other process (like the default Luckfox LED blinker) is using the pins.
2. Check `cat /sys/kernel/debug/gpio` to see which pins are currently claimed by the kernel.

Here is the updated **References** block to include at the end of your `README.md`. This captures the specific hardware you're using (the new Luckfox Lyra "Pi" form factor and the Waveshare-style SX1262 HAT) along with the core software projects that made this possible.

---

### 📚 References & Resources

#### Hardware

* **[Luckfox Lyra Pi](https://wiki.luckfox.com/Luckfox-Lyra/Introduction/)** - An RK3506 quad-core IoT development board. Features dual Ethernet (one with PoE) and a Pi-compatible 40-pin header.
* **[Waveshare SX1262 LoRa HAT](https://www.google.com/search?q=https://www.waveshare.com/sx1262-915m-lora-hat.htm)** - A high-performance LoRa expansion board using UART/SPI, commonly used for Meshtastic and custom mesh nodes.

#### Core Software & Drivers

* **[pyMC_Repeater](https://github.com/rightup/pyMC_Repeater)** - The lightweight Python-based MeshCore repeater daemon that handles the LoRa packet flooding logic.
* **[Luckfox-Pico SDK](https://github.com/LuckfoxTECH/luckfox-pico)** - The official SDK for building and troubleshooting the Rockchip-based images used on this hardware.
* **[Deadsnakes PPA](https://github.com/deadsnakes/issues)** - The community-maintained repository used to pull Python 3.11+ onto Ubuntu 22.04 LTS.

#### Documentation

* **[Luckfox Wiki (Official)](https://wiki.luckfox.com/Luckfox-Lyra/Luckfox-Lyra-Plus/)** - Official technical documentation for flashing, pinouts, and SDK compilation.
* **[MeshCore Documentation](https://www.google.com/search?q=https://github.com/topics/meshcore)** - Background on the underlying mesh protocol used by the `pymc` stack.
