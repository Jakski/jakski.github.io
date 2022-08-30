The more technologies I work with the more sophisticated are my development
environments. In scripting languages everything usually boils down to having
intepreter in relevant version. Problem begins when I work with extensions
compiled to native processor executable code or lower level projects. Things are
getting really messy when I have to partially provision infrastructure to test
solutions. Of course virtualization is the best for these kind of problems and a
lot of solutions exist:

- Vagrant - The idea is noble. It allows us to universally define environment in
  terms of *boxes*, *providers* and *provisioners*. Problem is: Vagrant works
  only as an orchestrator. We still need to separately provide virtualization
  platform and ensure that they will work together nicely. From my experience
  it's not much of a problem, but sometimes you need to define platform specific
  overrides or plugins. That's where versatility of this solution looses it's
  charm. We may use some useful optimizations for QEMU + KVM + libvirt stack,
  but what if someone is using VirtualBox or VMWare? We generally need to
  consider every platform where our project is to be developed.
- Docker and Docker Compose - To be honest it's one of the most developer
  friendly solutions for provisioning development environments, that I worked
  with. Not without downsides though. Containers don't run their own kernel.
  It's not a problem, if your code runs solely in userspace but things get
  tricky when you need e.g.: to install VPN modules into kernel. Security is
  also a problem here, if you use Linux. Remember that access to your system
  user means access to Docker UNIX socket which means administrative access to
  system. Docker requires administrative permissions to create containers. It's
  possible to run it in so-called *rootless* mode, but it has it's downsides as
  well.
- Cloud environments - Why not just maintain instance image in some cloud
  provider? This way you can simply spawn new instances from snapshot whenever
  you need a new environment or even combine them with other services in
  Terraform. First problem is that you need to secure them properly. Publicly
  exposed IPs aren't always acceptable. Secondly you must actually trust cloud
  provider. It's not as obvious as it sounds, since some projects require a high
  level of compliance with security standards and shouldn't be developed on
  cheap VPSes. Thirdly you need to have some continuous integration in place.
  Even if it's something so trivial like deployment script executed from
  developer's laptop upon saving a code. Without it working with remote
  environment will be a hassle.
- Manually crafted appliances - Probably the fastest approach. Someone in team
  just prepares virtual machine image with everything included and distributes
  it to other programmers. Updating this image later is a senseless chore, but
  apart from massively consuming time, it gets the job done. Often times it's
  not practical, unless everyone has good access to internet or sit in the same
  office. It takes time before someone uploads a few(usually more) gigabytes.

# Idea

I was thinking of a few approaches:

- Hashicorp Packer image templates - Performing installation from bottom-up with
  preseeding would be a quite complete solution. The problem is I don't really
  benefit from creating images from scratch each time and hosting prebuilt
  images would introduce some third party service to setup apart from code
  repository.
- virt-builder from libguestfs tools - Similar tool to Packer, but images are
  only adjusted and not built from scratch. Whole package is really nicely
  geared towards end-user, but underneath a lot of things happen. libguestfs is
  designed to spawn a tiny appliance for crafting images. Also base images are
  by default downloaded from non-official sources. It would be cool to be
  dependent only on distribution's official images without introducing anyone in
  the middle.
- Bootstrapped images from chroot environment - Most distributions provide tools
  like debootstrap for installing system. Of course more things are needed to
  successfully prepare working image like configuring system boot, language and
  partitioning. I tried to do it all with
  [mkimage.sh](https://github.com/Jakski/scripts/blob/cdd9c49c1e1c3be6926653b7323b208b7325d39d/sandbox/mkimage.sh),
  but at some point administrative privileges were required to ensure proper
  file permissions and craft image with loop devices. This method is also
  highely dependent on host system to provide required utilities for managing
  file systems and disks. It was a nice experiment, but whole process is too
  error-prone and hard to reproduce.

So is there another way? First let's limit the scope to just solutions working
with QEMU + KVM stack. After seeing the tricks people did to make Docker run on
Windows and MacOS I give up the hope that there's a universal way to provision
development infrastructure on all platforms. If something works "everywhere" it
usually means that some company spent a lot of time to ensure compatibility with
every popular platform. I don't want any complicated solutions. I just want to
be able to spin up development instance for each of my projects ad-hoc on
Debian.

I recently had a pleasure to work with
[cloud-init](https://wiki.archlinux.org/title/Cloud-init) which makes it really
easy to provision new instances on-fly. But how cloud-init gets information on
how to provision instance and can I use it without using a cloud service? It
turns out that there're a lot of methods and they are called
[datasources](https://cloudinit.readthedocs.io/en/latest/topics/datasources.html)
in documentation. In public clouds it's usually assumed that some network
service will expose metadata, but there's more. Metadata can be also provided on
CD image attached to instance. It's great cause it means that we can use
cloud-init with practically any virtualization platform including QEMU. Let's
try to implement the following flow:

1. ISO 9660 with provisioning information is created. It contains user access
   keys and any required installation scripts.
2. QEMU launches instance with metadata CD. It may be also a good place to use
   virtiofs for exposing directories with project from host system. AppArmor
   profile would be welcome as well.
3. Developer logs into machine or just sends SSH commands to recompile and rerun
   tests.

# Generating base image

Fortunately Debian provides [official cloud
images](https://cdimage.debian.org/images/cloud/), which already contain
cloud-init. Since we use QEMU all devices will be provided via *virtio*, we can
pick *genericcloud* variant. cloud-init provides some tool for creating
datasource image, but we can also do it with any ISO manipulation tool:

```shell
$> cat > meta-data
instance-id: devbox
local-hostname: devbox
$> cat > user-data
#cloud-config
ssh_authorized_keys:
  - $(cat "${HOME}/.ssh/id_rsa.pub" | tr -d "\n")
$> genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data
```

Provisioning parameters are split into *meta-data* traditionally provided by
hosting platform and *user-data*, where we can place our own customizations. In
this case we use meta-data to provide minimal information for identification.

# Launching instance

cloud-init will begin provisioning upon startup, so we don't have to do
anything. The only exception is when you use `package_reboot_if_required` flag,
which(as name suggests) restart our instance additionally in some cases.

```shell
$> qemu-system-x86_64 \
  -m 256 \
  -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
  -drive file=instance.qcow2,if=virtio \
  -drive driver=raw,file=seed.iso,if=virtio
```

This is far from optimal, since out network card is implemented in user-space
and burns CPU, but it's good enough for now. Take a note that we also expose
port 22 to host network, so that we can login via SSH like this:

```shell
$> ssh debian@127.0.0.1 -p 2222
```

*debian* is the default user for official cloud images. We could also change
default user or provision a few users using `users` key. You can find a
documentation for all cloud-init modules
[here](https://cloudinit.readthedocs.io/en/latest/topics/modules.html).

If you scheduled package installation in cloud-config, it might be worth
checking provisioning status before starting any work:

```shell
$> cloud-init status
status: done
```

# Using host directory

In theory above setup would be enough for most of things, but can take things
even further. Instead of synchronizing code to virtual machine or setting up
development environment remotely, we can mount code directly. QEMU allows us to
do it in at least 2 ways:

- 9p over virtio(VirtFS) virtualization framework
- virtio-fs which is to my understanding better optimized for interactions with
  hypervisor 

I really wanted to do it with virtio-fs, but it requires root daemon `virtiofsd`
to be running on hypervisor. It's not like it's a blocker, but for now we want
to keep things simple, so let's stick to VirtFS. With VirtFS using host
directory is just a matter of adding flags to QEMU:

```
-fsdev local,id=code0,path="$(realpath .)",security_model=mapped-xattr \
-device virtio-9p-pci,fsdev=code0,mount_tag=code
```

and mounting it inside virtual machine like so:

```shell
$> mount -t 9p -o trans=virtio code /mnt
```

If you're using *genericcloud* Debian image, than you will be warned about
unknown filesystem type:

```shell
root@devbox:~# mount -t 9p -o trans=virtio code /mnt
mount: /mnt: unknown filesystem type '9p'.
```

It is, because minimal Debian image ships without any extra drivers beside
paravirtualization support. Once you use *generic* image this problem will go
away. Automatic mounting can be configured with cloud-init like this:

```yaml
mounts:
  - [code, /mnt, 9p, trans=virtio, "0", "0"]
```

# Optimizations

## CPU acceleration

If you try to recreate this setup, you've probably noticed that virtual machine
literally burns your CPU. Using virtualization processor extensions like VTx is
a quickwin here. On Linux they are utilized by KVM. Note that your user must
have access to */dev/kvm* in order to use this acceleration. Under Debian it's a
matter of adding user to group *kvm*. Then you can use command `kvm` instead of
QEMU(it's still QEMU underneath) or add `-enable-kvm` flag.

## Virtual network interface instead of user networking

User networking is quick and easy, but it also involves emulating network stack
on top of hypervisor's network stack. We can improve it by using TAP interfaces,
which are connected to bridge on hypervisor. There are countless ways to
configure bridge interfaces, so let's use *ifup* scripts on Debian with
*nftables* to implement packet masquerading. In order to allow configuring
bridges in *interfaces* you will need extra package:

```shell
$> apt install bridge-utils
```

In */etc/network/interfaces.d/devbox*:

```
auto br0
iface br0 inet static
  bridge_ports none
  bridge_stp off
  address 192.168.2.1
  network 192.168.2.0
  netmask 255.255.255.0
  broadcast 192.168.2.255
```

We will use static address configuration, because DHCP will be provided by
*dnsmasq* and we want it to bind only to manged interfaces(`bind-interfaces`) to
prevent it from interfering accidentally with other system services.

```shell
$> apt install dnsmasq
```

Normally *dnsmasq* works greate out of the box, but in this case we want to
explicitly limit its job to single interface. Configuration is stored in
*/etc/dnsmasq.conf* on Debian:

```
interface=br0
except-interface=lo
listen-address=192.168.2.1
bind-interfaces
dhcp-range=192.168.2.0,static,1m
dhcp-host=devbox,192.168.2.2
dhcp-option=br0,option:router,192.168.2.1
```

Until now we effectively enabled communication between virtual machine and host,
but we also want to share internet access. Linux requires changing kernel
options before it starts forwarding packets:

```
$> sysctl -w net.ipv4.ip_forward=1
```

> **Caution**: Turning on packet forwarding might impose some security risks, if
> you don't trust your network. It's best to enable it only after you configure
> basic firewall rules.

Last thing to do is NATting, so that packets sent by virtual machine will be
seen like in network with proper source address. This can be achieved in
multiple ways, but I will stick to *nftables*:

```
$> apt install nftables
```

In */etc/nftables.conf*:

```
#!/usr/sbin/nft -f

flush ruleset

table inet nat {
  chain postrouting {
    type nat hook postrouting priority 0
    iifname br0 masquerade
  }
}

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop
    meta iif lo accept
    meta iif br0 accept
    ct state established,related accept
    ct state invalid drop
  }
  chain forward {
    type filter hook forward priority 0; policy drop
    ct state related,established accept
    iifname br0 accept
  }
  chain output {
    type filter hook output priority 0;
  }
}
```

Note that above rules allow to access every network that your host can,
including home/office internal networks.

Since QEMU uses separate bridge helper tool to enable interface manipulation, we
will need to setup privileges appropriately:

```shell
$> setcap cap_net_admin+ep /usr/lib/qemu/qemu-bridge-helper
$> cd /etc/qemu/
$> cat bridge.conf
include /etc/qemu/jakski-bridge.conf
$> cat jakski-bridge.conf
allow br0
$> ls -alrth
total 24K
-rw-r-----   1 root jakski   10 Aug 29 17:51 jakski-bridge.conf
-rw-r--r--   1 root root     37 Aug 29 17:51 bridge.conf
drwxr-xr-x   2 root root   4.0K Aug 29 17:51 .
drwxr-xr-x 154 root root    12K Aug 30 04:47 ..
```

Note how file permissions are set up on helper ACLs. Mode and ownership are
crucial to ensure that only selected user can attach interfaces to our bridge.

Now we're ready to launch virtual machine with optimal network setup:

```shell
kvm \
  -m 256 \
  -nic bridge,br=br0,model=virtio-net-pci \
  -drive file=instance.qcow2,if=virtio \
  -drive driver=raw,file=seed.iso,if=virtio \
  -fsdev local,id=code0,path="$(realpath .)",security_model=mapped-xattr \
  -device virtio-9p-pci,fsdev=code0,mount_tag=code
```

## virtio-fs

TODO
