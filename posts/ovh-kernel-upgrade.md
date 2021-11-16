Recently I noticed that despite upgrading kernel on my OVH VPS it's still using
old version. After some research I discovered that OVH base image(Debian 8, VPS
2016 SSD 1) uses extlinux to manage master boot record. While I was used to self
updating GRUB configuration, extlinux didn't point to new kernel automatically
after upgrade. I found it's configuration in
*/boot/extlinux/extlinux.conf*:

```
default linux
timeout 1
label linux
kernel boot/vmlinuz-3.16.0-4-amd64
append initrd=boot/initrd.img-3.16.0-4-amd64 root=/dev/vda1 console=tty0
console=ttyS0,115200 ro quiet
```

changed paths to initial RAM disk and Linux image:

```
default linux
timeout 1
label linux
kernel ../vmlinuz-4.9.0-8-amd64
append initrd=../initrd.img-4.9.0-8-amd64 root=/dev/vda1 console=tty0
console=ttyS0,115200 ro quiet
```

and updated extlinux with:

```
$ extlinux --install /boot/extlinux
```

After reboot extlinux loaded fresh kernel.
