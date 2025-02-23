# make-libvirt-coreos

Create Fedora CoreOS VM's using libvirt and butane "templates".

## Description

This repository contains a Makefile which makes it easier to launch CoreOS virtual machines which are automatically initialized according to a butane generated ignition file. The word abomination is probably a good description of the code but it works for me on my computer so I'm happy.

The whole goal of this Makefile is to quickly create a VM, test something and then destroy it again. No Ansible, no Terraform, no building images, just a VM that initializes itself on boot.

## Prerequisites
For the script to work you'll need
* make
* libvirt
* virt-install
* virt-manager (easy UI to manage the VM's)
* virt-viewer (if SSH doesn't work)
* podman

To install those on an Arch based OS you can run

`sudo pacman -Sy libvirt virt-install virt-viewer podman`

If you want to use the Makefile to download the latest VM image, you'll need
* jq
* xz
* curl
* wget
* sha256sum

`sudo pacman -Sy jq xz curl wget openssl`

The assumption is that there's already a virtd network called `bridged-network`, you can follow [this](http://blog.leifmadsen.com/blog/2016/12/01/create-network-bridge-with-nmcli-for-libvirt/) guide.

## How to use the Makefile

Each VM will have it's own `PROJECT` folder which must contain a `make.env` file containing the VM's parameters. An example of such file is:
```
PROJECT_NAME = coreos-borg-1
BUTANE=borg.conf
IGN_HOSTNAME = $(PROJECT_NAME)
IGN_IP = 10.0.12.12

VM_NAME = $(PROJECT_NAME)
VCPUS = 2
RAM_MB = 2048
DISK_GB = 10
IMAGE = "$(PWD)/coreos.qcow2"
```

Let's put this in `test/make.env`

New you'll need a Butane template, for the above example the template must be in `templates/borg.conf`

```
variant: fcos
version: 1.6.0
passwd:
  users:
    - name: core
      ssh_authorized_keys: 
        - "ssh-ed25519 YOUR PUBLIC KEY DO NOT SKIP THIS"
      shell: /bin/bash
storage:
  files:
    - path: /etc/systemd/zram-generator.conf
      mode: 0644
      contents:
        inline: |
          # This config file enables a /dev/zram0 device with the default settings
          [zram0]
          zram-size = ram / 2
          compression-algorithm = lzo
    - path: /etc/profile.d/zz-default-editor.sh
      overwrite: true
      contents:
        inline: |
          export EDITOR=vim
    - path: /etc/hostname
      mode: 0644
      contents:
        inline: ${IGN_HOSTNAME}
    - path: /etc/vconsole.conf
      mode: 0644
      contents:
        inline: KEYMAP=be
    - path: /etc/NetworkManager/system-connections/ens2.nmconnection
      mode: 0600
      contents:
        inline: |
          [connection]
          id=enp1s0
          type=ethernet
          interface-name=enp1s0
          [ipv4]
          address1=${IGN_IP}/16,10.0.0.1
          dns=1.1.1.1;8.8.8.8
          may-fail=false
          method=manual
systemd:
  units:
    # Install tools as a layered package with rpm-ostree
    - name: rpm-ostree-install-tools.service
      enabled: true
      contents: |
        [Unit]
        Description=Layer tools with rpm-ostree
        Wants=network-online.target
        After=network-online.target
        # We run before `zincati.service` to avoid conflicting rpm-ostree
        # transactions.
        Before=zincati.service
        ConditionPathExists=!/var/lib/%N.stamp

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        # `--allow-inactive` ensures that rpm-ostree does not return an error
        # if the package is already installed. This is useful if the package is
        # added to the root image in a future Fedora CoreOS release as it will
        # prevent the service from failing.
        ExecStart=/usr/bin/rpm-ostree install -y --allow-inactive vim borgbackup qemu-guest-agent
        ExecStart=/bin/touch /var/lib/%N.stamp
        ExecStart=/bin/systemctl --no-block reboot

        [Install]
        WantedBy=multi-user.target

```

In the above example, the IP address of the VM will be `10.0.12.12/16` with a gateway IP of `10.0.0.0.1`.

To launch the VM run
```
export set PROJECT=test
make download
make
```

## Targets
There are a couple of targets

### ignite
Uses the Butane template to create a VM specific Butane file and then converts it to an ignite file.
The final ignite file which will be used by the VM is located in `/home/$(USER)/.config/libvirt/ignition/$(PROJECT).ign`

### launch
Creates the VM. Keep in the mind that the VM will reboot a couple of times before it's ready to use.

### delete
Stops the VM and removes all files.

### destroy
Stops the VM.

### ssh
Opens an SSH session to the VM.

### download
Downloads the latest VM base image from Fedora, extracts it and verifies the SHA256 hash.

### clean-download
Removes the base VM image.