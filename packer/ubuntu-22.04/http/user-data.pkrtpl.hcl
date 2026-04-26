#cloud-config
autoinstall:
  version: 1
  locale: en_US
  keyboard:
    layout: us
  network:
    version: 2
    ethernets:
      any:
        match:
          name: "en*"
        addresses:
          - 172.16.0.100/24
        gateway4: 172.16.0.254
        nameservers:
          addresses: [1.1.1.1, 8.8.8.8]
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
    #- qemu-guest-agent -> bug during installation
    - cloud-init
  late-commands:
    - "echo '${build_username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/${build_username}"
    - "chmod 440 /target/etc/sudoers.d/${build_username}"
