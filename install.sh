#!/bin/bash

# This is a rewritten version of github.com/Hinara/linux-vm-tools/master/ubuntu/24.04/install.sh
# Tailored for Linux Mint Cinnamon

# Function to handle reboot
function askForReboot() {
  read -p "Reboot now? [Y,n] " -n 1 -r
  echo # (optional) move to a new line
  if [[ $REPLY =~ ^[Yy]$ || -z $REPLY ]]; then
    reboot
  fi
}

# exit script on error
set -e

# Check if script run as root
if [ "$(id -u)" -ne 0 ]; then
  echo 'This script must be run with root privileges' >&2
  exit 1
fi

# Make sure system is in good shape
apt update
if [ $? -ne 0 ]; then
  echo "Error on updating"
  exit 1
fi
apt upgrade -y
apt autoremove

# Check if reboot is needed
if [ -f /var/run/reboot-required ]; then
  echo "A reboot is required in order to proceed with the install." >&2
  echo "Please reboot and re-run this script to finish the install." >&2
  askForReboot
  exit 1
fi

# install hv_kvp utils
apt install -y linux-tools-virtual
apt install -y linux-cloud-tools-virtual

# installing xrdp and xorgxrdp for support of RDP
# installing pipewire-xrdp for support for redirecting audio (Linux Mint uses PipeWire)
apt install -y xrdp xorgxrdp pipewire-module-xrdp libpipewire-0.3-modules-xrdp

# stopping services
systemctl stop xrdp
systemctl stop xrdp-sesman

# Configure the installed XRDP ini files.
# Use vsock transport.
sed -i_orig -e 's/port=3389/port=vsock:\/\/-1:3389/g' /etc/xrdp/xrdp.ini
# Use RDP security.
sed -i_orig -e 's/security_layer=negotiate/security_layer=rdp/g' /etc/xrdp/xrdp.ini
# Remove encryption validation.
sed -i_orig -e 's/crypt_level=high/crypt_level=none/g' /etc/xrdp/xrdp.ini
# Disable bitmap compression since it's local, it's much faster
sed -i_orig -e 's/bitmap_compression=true/bitmap_compression=false/g' /etc/xrdp/xrdp.ini

# Add script to set up the session properly
if [ ! -e /etc/profile.d/xrdp-setup.sh ]; then
  cat >>/etc/profile.d/xrdp-setup.sh <<EOF
#!/bin/bash
export DESKTOP_SESSION=cinnamon
export XDG_CURRENT_DESKTOP=X-Cinnamon
EOF
  chmod a+x /etc/profile.d/xrdp-setup.sh
fi

# Allow everyone to create an X server
sudo tee /etc/X11/Xwrapper.config >/dev/null <<EOL
# Xwrapper.config (Debian X Window System server wrapper configuration file)
needs_root_rights=no
allowed_users=anybody
EOL

# Rename the redirected drives to 'shared-drives'
sed -i -e 's/FuseMountName=thinclient_drives/FuseMountName=shared-drives/g' /etc/xrdp/sesman.ini

# Blacklist the vmw module
if [ ! -e /etc/modprobe.d/blacklist-vmw_vsock_vmci_transport.conf ]; then
  echo "blacklist vmw_vsock_vmci_transport" >/etc/modprobe.d/blacklist-vmw_vsock_vmci_transport.conf
fi

# Ensure hv_sock gets loaded
if [ ! -e /etc/modules-load.d/hv_sock.conf ]; then
  echo "hv_sock" >/etc/modules-load.d/hv_sock.conf
fi

# Configure the policy for the XRDP session
mkdir -p /etc/polkit-1/localauthority/50-local.d/
cat >/etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla <<EOF
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

# Reconfigure the service
systemctl daemon-reload
systemctl enable --now xrdp
systemctl enable --now xrdp-sesman

# Enable services related to Hyper-V integration services
systemctl enable hv-fcopy-daemon.service
systemctl enable hv-kvp-daemon.service
systemctl enable hv-vss-daemon.service

echo "Install is complete."
echo "Reboot your machine to begin using XRDP."
askForReboot
