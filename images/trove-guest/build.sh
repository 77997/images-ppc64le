#!/bin/bash
# Builds one Trove guest disk, as root on a GitHub-hosted x86 runner, from Debian's latest trixie
# "generic" cloud image (Debian publishes no "genericcloud" image for ppc64el). Debian's
# partitions and bootloader stay as Debian made them: the disk is grown, its root filesystem
# mounted from a loop device and customised in a chroot by customise.sh, under qemu-user
# emulation for ppc64le, then compressed back to qcow2 with its checksum and the versions it holds.
#
# ARCH                     amd64 or ppc64le
# TROVE_URL, TROVE_SHA256  the Trove tarball kolla installs, with the digest resolved for this run
# REQUIREMENTS_URL, REQUIREMENTS_SHA256
#                          the requirements tarball kolla installs, whose upper-constraints the
#                          agent is installed with
# OUT                      the directory the disk, its .sha256 and its .versions go to
set -euo pipefail

: "${ARCH:?}" "${TROVE_URL:?}" "${TROVE_SHA256:?}" "${REQUIREMENTS_URL:?}" "${REQUIREMENTS_SHA256:?}" "${OUT:?}"

# The build mounts in a mount namespace of its own: a mount made in the host's would propagate
# into the private namespaces of systemd's services (udevd, resolved, timesyncd, networkd,
# logind), which would keep the root filesystem in use after it is unmounted here, so the disk
# would be converted while that filesystem is still mounted.
if [ -z "${TROVE_GUEST_OWN_MOUNTS:-}" ]; then
    exec env TROVE_GUEST_OWN_MOUNTS=1 unshare --mount --propagation private "$0" "$@"
fi

PIP_INDEX=""
case "$ARCH" in
    amd64) DEBIAN_ARCH=amd64 ;;
    # kolla's openstack-base takes ppc64le's compiled wheels from the same index
    ppc64le) DEBIAN_ARCH=ppc64el; PIP_INDEX=https://77997.github.io/images-ppc64le/simple/ ;;
    *) echo "Unknown architecture $ARCH"; exit 1 ;;
esac
# Debian's 3 GiB disk leaves too little room for the element's packages, Docker CE and the venv.
SIZE=4G
DISK="trove-guest-debian-13-$ARCH"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
ROOT="$WORK/root"
LOOP=""

cleanup() {
    if mountpoint -q "$ROOT"; then umount -R "$ROOT"; fi
    if [ -n "$LOOP" ]; then losetup -d "$LOOP"; fi
    # Never into a filesystem still mounted under the work directory, such as the bound /dev.
    rm -rf --one-file-system "$WORK"
}
trap cleanup EXIT

fetch() {
    curl -fsSL --retry 3 --max-time 1800 -o "$2" "$1"
}

# Debian's latest trixie generic image for this architecture, checked against Debian's checksums
VERSION="$(curl -fsSL --retry 3 "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-$DEBIAN_ARCH.json" \
    | jq -r '.items[] | select(.kind == "Build") | .data.info.version')"
[ -n "$VERSION" ] && [ "$VERSION" != null ] || { echo "Debian image version resolution failed"; exit 1; }
NAME="debian-13-generic-$DEBIAN_ARCH-$VERSION"
BASE="https://cloud.debian.org/images/cloud/trixie/$VERSION"
echo "Resolved $NAME"
fetch "$BASE/$NAME.qcow2" "$WORK/base.qcow2"
EXPECTED="$(curl -fsSL --retry 3 "$BASE/SHA512SUMS" | awk -v f="$NAME.qcow2" '$2 == f { print $1 }')"
[ -n "$EXPECTED" ] || { echo "Debian's SHA512SUMS holds no $NAME.qcow2"; exit 1; }
echo "$EXPECTED  $WORK/base.qcow2" | sha512sum -c -

# Trove and kolla's upper-constraints, as resolved for this run
fetch "$TROVE_URL" "$WORK/trove.tar.gz"
echo "$TROVE_SHA256  $WORK/trove.tar.gz" | sha256sum -c -
fetch "$REQUIREMENTS_URL" "$WORK/requirements.tar.gz"
echo "$REQUIREMENTS_SHA256  $WORK/requirements.tar.gz" | sha256sum -c -

qemu-img convert -f qcow2 -O raw "$WORK/base.qcow2" "$WORK/disk.raw"
rm "$WORK/base.qcow2"
qemu-img resize -f raw "$WORK/disk.raw" "$SIZE"

# The disk's one ext4 filesystem is its root; grow its partition and filesystem into the new space.
LOOP="$(losetup --find --show --partscan "$WORK/disk.raw")"
ROOTS=()
for part in "$LOOP"p*; do
    if [ "$(blkid -o value -s TYPE "$part" || true)" = ext4 ]; then ROOTS+=("$part"); fi
done
[ "${#ROOTS[@]}" -eq 1 ] || { echo "Expected one ext4 partition on $LOOP, found ${#ROOTS[@]}"; lsblk -o NAME,SIZE,FSTYPE "$LOOP"; exit 1; }
PART="${ROOTS[0]}"
growpart "$LOOP" "${PART##*p}"
e2fsck -fy "$PART" || [ $? -eq 1 ]
resize2fs "$PART"

mkdir "$ROOT"
mount "$PART" "$ROOT"
mount --rbind /dev "$ROOT/dev"
mount --make-rslave "$ROOT/dev"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sysfs "$ROOT/sys"
mount -t tmpfs tmpfs "$ROOT/run"
mount -t tmpfs tmpfs "$ROOT/tmp"

# What the chroot changes for its own run and puts back afterwards: the resolver, the machine id,
# and no service starting in the chroot.
cp -a "$ROOT/etc/resolv.conf" "$WORK/resolv.conf"
cp -a "$ROOT/etc/machine-id" "$WORK/machine-id"
mapfile -t HOST_KEYS < <(find "$ROOT/etc/ssh" -maxdepth 1 -name 'ssh_host_*' -printf '%f\n')
[ ! -e "$ROOT/usr/sbin/policy-rc.d" ] || { echo "Debian's image already holds a policy-rc.d"; exit 1; }
rm -f "$ROOT/etc/resolv.conf"
cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$ROOT/usr/sbin/policy-rc.d"
chmod 0755 "$ROOT/usr/sbin/policy-rc.d"

mkdir -p "$ROOT/opt/guest-agent" "$ROOT/tmp/trove-guest" "$WORK/requirements"
tar -xzf "$WORK/trove.tar.gz" -C "$ROOT/opt/guest-agent" --strip-components 1
tar -xzf "$WORK/requirements.tar.gz" -C "$WORK/requirements" --strip-components 1
cp "$WORK/requirements/upper-constraints.txt" "$ROOT/opt/upper-constraints.txt"
cp "$HERE/customise.sh" "$HERE/after-cloud-config.conf" "$HERE/90-trove-datasource.cfg" \
    "$HERE/91-trove-default-user.cfg" "$ROOT/tmp/trove-guest/"

chroot "$ROOT" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C.UTF-8 \
    ${PIP_INDEX:+PIP_EXTRA_INDEX_URL="$PIP_INDEX"} \
    /bin/bash /tmp/trove-guest/customise.sh
cp "$ROOT/tmp/trove-guest/versions" "$WORK/versions"

rm -f "$ROOT/usr/sbin/policy-rc.d" "$ROOT/etc/resolv.conf"
cp -a "$WORK/resolv.conf" "$ROOT/etc/resolv.conf"
cp -a "$WORK/machine-id" "$ROOT/etc/machine-id"
find "$ROOT/etc/ssh" -maxdepth 1 -name 'ssh_host_*' -printf '%f\n' | while read -r key; do
    printf '%s\n' "${HOST_KEYS[@]}" | grep -qxF "$key" || rm -f "$ROOT/etc/ssh/$key"
done

umount -R "$ROOT/tmp" "$ROOT/run" "$ROOT/sys" "$ROOT/proc" "$ROOT/dev"
fstrim "$ROOT"
umount "$ROOT"
# A read-only check passes only when the filesystem was cleanly unmounted and nothing holds it.
e2fsck -fn "$PART"
losetup -d "$LOOP"
LOOP=""

mkdir -p "$OUT"
qemu-img convert -f raw -O qcow2 -c "$WORK/disk.raw" "$OUT/$DISK.qcow2"
(cd "$OUT" && sha256sum "$DISK.qcow2" > "$DISK.qcow2.sha256")
{
    echo "debian $NAME"
    cat "$WORK/versions"
} > "$OUT/$DISK.versions"
cat "$OUT/$DISK.versions"
