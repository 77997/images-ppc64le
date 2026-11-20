#!/bin/bash
# Runs as root inside the root filesystem of a Trove guest disk, started by build.sh. It does
# to Debian's trixie cloud image what Trove's guest-agent, ubuntu-guest and ubuntu-docker
# elements do to an Ubuntu image, from the element files of the Trove source at /opt/guest-agent,
# which build.sh unpacks from the tarball kolla installs, with kolla's upper-constraints at
# /opt/upper-constraints.txt.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
GUEST_USERNAME=trove
GUEST_VENV=/opt/guest-agent-venv
ARCH="$(dpkg --print-architecture)"
ELEMENTS=/opt/guest-agent/integration/scripts/files/elements
SCRIPTDIR="$ELEMENTS/guest-agent/install.d/guest-agent-source-install"
HERE=/tmp/trove-guest
APTOPTS=(-y -qq --no-install-recommends)

# The guest-agent element's packages for this architecture, less Ubuntu's own
# (ubuntu-cloudimage-keyring, ureadahead, pollinate), those that would replace Debian's netplan
# and systemd-networkd setup (ifupdown, ifenslave, isc-dhcp-client), iptables-persistent, whose
# installation would save the build machine's firewall rules into the image, and the agent,
# which comes from source below.
mapfile -t PACKAGES < <(python3 - "$ELEMENTS/guest-agent/package-installs.yaml" "$ARCH" <<'PY'
import sys

import yaml

SKIP = {"guest-agent", "ubuntu-cloudimage-keyring", "ureadahead", "pollinate", "ifupdown", "ifenslave",
        "isc-dhcp-client", "iptables-persistent"}
with open(sys.argv[1]) as source:
    packages = yaml.safe_load(source)
for name, options in packages.items():
    arches = [a.strip() for a in str((options or {}).get("arch", "")).split(",") if a.strip()]
    if name not in SKIP and (not arches or sys.argv[2] in arches):
        print(name)
PY
)
[ "${#PACKAGES[@]}" -gt 0 ] || { echo "The guest-agent element lists no package"; exit 1; }
apt-get update
apt-get install "${APTOPTS[@]}" "${PACKAGES[@]}"

# Docker CE from Docker's own Debian repository, as Docker's documentation installs it.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
printf '%s\n' 'Types: deb' 'URIs: https://download.docker.com/linux/debian' \
    "Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")" 'Components: stable' \
    "Architectures: $ARCH" 'Signed-By: /etc/apt/keyrings/docker.asc' > /etc/apt/sources.list.d/docker.sources
apt-get update
apt-get install "${APTOPTS[@]}" docker-ce docker-ce-cli containerd.io

# The guest user (ubuntu-guest's 11-user and 13-trove-guest-sudoers, ubuntu-docker's 21-docker),
# with no password, and cloud-init's default user, so the instance's key pair reaches it.
id -u "$GUEST_USERNAME" >/dev/null 2>&1 || useradd -G sudo -m -s /bin/bash "$GUEST_USERNAME"
install -D -g root -o root -m 0644 "$HERE/91-trove-default-user.cfg" /etc/cloud/cloud.cfg.d/91-trove-default-user.cfg
usermod -aG docker "$GUEST_USERNAME"
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$GUEST_USERNAME" > /etc/sudoers.d/60_trove_guest
chown root:root /etc/sudoers.d/60_trove_guest
chmod 0440 /etc/sudoers.d/60_trove_guest

# The guest agent, as guest-agent's 31-guest-agent-install installs it from source on systemd.
for folder in /var/lib/trove /etc/trove /etc/trove/certs /etc/trove/conf.d /var/log/trove /opt/trove-guestagent; do
    mkdir -p "$folder"
    chown -R "$GUEST_USERNAME:root" "$folder"
done
install -D -g root -o root -m 0644 "$SCRIPTDIR/guest-agent.logrotate" /etc/logrotate.d/guest-agent
/usr/bin/python3 -m venv "$GUEST_VENV"
"$GUEST_VENV/bin/pip" install pip --upgrade
"$GUEST_VENV/bin/pip" install -U -c /opt/upper-constraints.txt /opt/guest-agent
chown -R "$GUEST_USERNAME:root" "$GUEST_VENV"
install -D -g root -o root -m 0755 "$SCRIPTDIR/50-trove-image-loader" /usr/local/sbin/trove-image-loader
install -D -g root -o root -m 0644 "$SCRIPTDIR/trove-image-loader.service" /etc/systemd/system/trove-image-loader.service
ln -sf "$GUEST_VENV/bin/trove-docker-plugin" /usr/local/bin/trove-docker-plugin
install -D -g root -o root -m 0644 "$SCRIPTDIR/docker-hostnic.socket" /lib/systemd/system/docker-hostnic.socket
ln -sf "$GUEST_VENV/bin/trove-guestagent" /usr/local/bin/guest-agent
install -D -g root -o root -m 0644 "$SCRIPTDIR/docker-hostnic.service" /lib/systemd/system/docker-hostnic.service
sed "s/GUEST_USERNAME/$GUEST_USERNAME/g" "$SCRIPTDIR/guest-agent.service" > /etc/systemd/system/guest-agent.service

# Trove's units read the files cloud-init writes from the config drive into /etc/trove/conf.d,
# so they start after cloud-init has written them, and cloud-init reads the config drive alone.
for unit in guest-agent trove-image-loader; do
    install -D -g root -o root -m 0644 "$HERE/after-cloud-config.conf" "/etc/systemd/system/$unit.service.d/after-cloud-config.conf"
done
install -D -g root -o root -m 0644 "$HERE/90-trove-datasource.cfg" /etc/cloud/cloud.cfg.d/90-trove-datasource.cfg
systemctl enable guest-agent docker-hostnic.socket trove-image-loader

{
    echo "docker-ce $(dpkg-query -W -f='${Version}' docker-ce)"
    echo "containerd.io $(dpkg-query -W -f='${Version}' containerd.io)"
    echo "trove $("$GUEST_VENV/bin/pip" show trove | sed -n 's/^Version: //p')"
    echo "python3 $(python3 -c 'import platform; print(platform.python_version())')"
} > "$HERE/versions"

# guest-agent's 99-clean-apt
apt-get -y autoremove --purge
apt-get clean
rm -rf /var/lib/apt/lists/*
