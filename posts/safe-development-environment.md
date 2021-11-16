While QEMU/KVM based virtualization is usually used only with higher level
abstraction layers like *libvirt*, it can be still handy to launch virtual
machines without being system administrator. This article explains how to
implement simple virtualization platform with few assumptions:

- unprivileged user has access to *kvm* (usually adding user to *kvm* group is
  enough)
- host system is running systemd
- virtual machines will be using SLIRP networking with port forward to SSH
  from host system

# Creating base system image

Before running any new machines base system installation is required. It can be
created via VNC connection. Let's start by downloading and launching
installation process:

```
$ wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-9.4.0-amd64-netinst.iso
$ qemu-img create -f qcow2 debian9.qcow2 10G
$ qemu-system-x86_64 -enable-kvm -name debian -m 1024 -smp 2 \
  -cdrom /home/rayv/debian-9.4.0-amd64-netinst.iso \
  -drive file=/home/rayv/debian9.qcow2,if=virtio,format=qcow2 \
  -vnc 0.0.0.0:5,password,tls -k en-us -net nic -net user \
  -monitor stdio
```

Set password in freshly started QEMU monitor console:

```
(qemu) change vnc password
Password: ***
```

QEMU should expose VNC on port 5905. You can connect to it with program like
[Vinagre](https://wiki.gnome.org/Apps/Vinagre/). Install operating system on
attached virtual disk and shutdown.

> You can check, where VNC started listening with command: `$ ss -ltnp`.

# Configure systemd virtual machine service

Create directories for virtual machines configuration, serial and monitor
UNIX sockets:

```
$ mkdir ~/.config/qemu
$ mkdir ~/.config/systemd/user
$ mkdir ~/.qemu
```

Create service template for systemd in *~/.config/systemd/user/qemu@.service*:

```
[Unit]
Description=%i QEMU/KVM virtual machine
After=network.target

[Service]
EnvironmentFile=%h/.config/qemu/%i
ExecStart=/usr/bin/qemu-system-x86_64 -enable-kvm -name %i -m $MEMORY -smp $CPU $DRIVES -display none -monitor unix:%h/.qemu/%i-monitor.socket,server,nowait -serial unix:/home/rayv/.qemu/%i-serial.socket,server,nowait -device e1000,netdev=net0 -netdev user,id=net0,hostfwd=tcp:${SSH_ADDRESS}:${SSH_PORT}-:22
Type=simple
```

Paste configuration for your first virtual machine in *~/.config/qemu/vm1*:

```
MEMORY=2048
CPU=4
DRIVES="-drive file=/home/rayv/debian9.qcow2,if=virtio,format=qcow2 -drive file=/home/rayv/images.qcow2,if=virtio,format=qcow2"
SSH_ADDRESS="0.0.0.0"
SSH_PORT=5555
```

Remember to adjust configuration properly. In example above I've defined machine
with 2 block devices attached from my home directory, 2048 MiB of memory, 4
vCPUs and SSH port exposed on 5555 and all network interfaces on host system.
Remember that one of attached block devices must contain OS image for system
to boot.

# Start and connect to virtual machine

Reload systemd user instance, so it can detect new configuration:

```
$ systemctl --user daemon-reload
```

Start and get status of virtual machine from template service:

```
$ systemctl --user start qemu@vm1.service
$ systemctl --user status qemu@vm1.service
```

Now connect to virtual machine to user configured in installation process,
e.g.:

```
$ ssh guest_user@host_address -p 5555
```

# Using QEMU monitor and serial port

Serial port and monitor will be exposed as sockets in directory *~/.qemu*. You
can connect to them with *netcat*, but remember that your terminal will buffer
output and echo it to you, which may be not exactly what you want. You can
workaround it by changing terminal properties with *stty*. Here is a script to
ease connections to UNIX socket terminals:

```
#!/bin/bash

print_help() {
cat << EOF
Synopsis:
Connect to UNIX socket like to terminal. Special keybinds like Ctrl-C
and Ctrl-D won't work though.
Usage:
<PROGRAM> -s <SOCKET>
Options:
-h          print this message
-s SOCKET   connect to SOCKET
EOF
}

connect_console() {
 local path=$1
 stty -icanon -echo
 nc -U "$path"
 stty icanon echo
}

main() {
 while getopts ':hs:' opt
 do
    case "$opt" in
    'h')
       print_help
       exit 0
       ;;
    's')
       SOCKET=$OPTARG
       ;;
    '*')
       print_help
       exit 1
       ;;
    esac
 done
 connect_console $SOCKET
}

main $@
```
