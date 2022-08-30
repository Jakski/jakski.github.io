#!/usr/bin/env bash

set -euo pipefail -o errtrace
shopt -s inherit_errexit

IMAGE_URL="https://cdimage.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"

on_error() {
	declare cmd=$BASH_COMMAND exit_code=$?
	echo "Failing with code ${exit_code} in ${*} at command ${cmd}"
	exit "$exit_code"
}

render_user_data() {
cat << EOF
#cloud-config
ssh_authorized_keys:
  - $(cat "${HOME}/.ssh/id_rsa.pub" | tr -d "\n")
packages:
  - rsync
  - neovim
  - python3
  - python3-dev
  - python3-neovim
  - python3-pip
  - python3-venv
  - gcc
  - build-essential
  - curl
  - haveged
  - libffi-dev
  - libssl-dev
  - tmux
packages_update: true
packages_upgrade: true
package_reboot_if_required: true
mounts:
  - [code, /mnt, 9p, trans=virtio, "0", "0"]
EOF
}

render_meta_data() {
cat << EOF
instance-id: devbox
local-hostname: devbox
EOF
}

main() {
	trap 'on_error "${BASH_SOURCE[0]}:${LINENO}"' ERR
	render_user_data > user-data
	render_meta_data > meta-data
	rm -vf seed.iso
	genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data
	if [ ! -f base.qcow2 ]; then
		curl -sSL "$IMAGE_URL" > base.qcow2
	fi
	rm -vf instance.qcow2
	qemu-img create -f qcow2 -b base.qcow2 -F qcow2 instance.qcow2
	qemu-img resize instance.qcow2 +20G
	kvm \
		-m 256 \
		-nic bridge,br=br0,model=virtio-net-pci \
		-drive file=instance.qcow2,if=virtio \
		-drive driver=raw,file=seed.iso,if=virtio \
		-fsdev local,id=code0,path="$(realpath .)",security_model=mapped-xattr \
		-device virtio-9p-pci,fsdev=code0,mount_tag=code
}

main "$@"
