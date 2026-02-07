#!/bin/bash

# This will run a packer-built system
# It assumes builds are in /qemu/builds/packer-...

usage() {
    cat << USAGE
Usage: ./run-kvm [--bios] path-to-packer-build

Options:
  --bios    Run VM *without* UEFI bios
  --ram     Set ram size in MB
  --ssh     Set a port to allow SSH into the VM (default 2222)
            e.g. ssh -p 2222 packer@localhost -o pubkeyauthentication=no
            Since packer builds default to packer:packer creds

  path-to-packer-build should be a directory created by
  ./run-packer.sh - typically in /qemu/builds
USAGE
}

# Default ram 2GB
RAMSIZE="${RAMSIZE:-2048}"
SSH_PORT="${SSH_PORT:-2222}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bios)     BIOS=true ; shift ;;
    --ram)      RAMSIZE="$2" ; shift 2 ;;
    --ssh)      SSH_PORT="$2" ; shift 2 ;;
    --help)     usage; exit 0 ;;
    *)          ZFSROOT="$1" ; shift ;;
  esac
done

if [[ -z "$ZFSROOT" ]] ; then
    usage
    echo "Must provide a path to a packer build dir"
    if command -v fzf >/dev/null 2>&1; then
        echo "Pick one to boot or ESC to exit"
        ZFSROOT=$(find /qemu/builds/* -type d | fzf --height 20% --border --reverse --margin=5%,40%,0%,5%)
    else
        echo "For example, from here"
        find /qemu/builds/* -type d | xargs -I {} echo "$0 {}"
    fi
    [[ -z "$ZFSROOT" ]] && exit 1
fi

# If booting with UEFI we need the UEFI bios and saved efivars
if [[ -z "$BIOS" ]] ; then
    efivars=( -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd )
    efivars+=( -drive if=pflash,format=raw,file=${ZFSROOT}/efivars.fd )
fi

kvm -no-reboot -m ${RAMSIZE} \
    ${efivars[*]} \
    $(for f in ${ZFSROOT}/*qcow* ; do echo "-drive file=${f},format=qcow2,cache=writeback " ; done) \
    -device virtio-scsi-pci,id=scsi0 \
    -device virtio-net-pci,netdev=user.0 \
    -netdev user,id=user.0,hostfwd=tcp::${SSH_PORT}-:22 &
