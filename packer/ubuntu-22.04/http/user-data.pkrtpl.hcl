#cloud-config
autoinstall:
  version: 1
  locale: en_US
  keyboard:
    layout: us
  network:
    ethernets:
      ens18:
        dhcp4: true
    version: 2
  storage:
    layout:
      name: lvm
  identity:
    hostname: ubuntu-template
    username: ${build_username}
    password: "${build_password_encrypted}"
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - qemu-guest-agent
    - cloud-init
  late-commands:
    - "echo '${build_username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/${build_username}"
    - "chmod 440 /target/etc/sudoers.d/${build_username}"
