
set -eu

# Set root password
chpasswd < /setup/secrets/plasmon-password.secret

# Install ssh key
install -D -m 600 /setup/secrets/ssh-key.secret /root/.ssh/authorized_keys

# Install ZFS
cat >> /etc/pacman.conf <<-EOF
	[archzfs]
	Server = https://zxcvfdsa.com/archzfs/\$repo/\$arch
	Server = http://archzfs.com/\$repo/x86_64
EOF
pacman-key --add /setup/images/plasmon/archzfs.gpg
pacman-key --lsign-key DDF7DB817396A49B2A2723F7403BD972F75D9D76
pacman -Sy --noconfirm zfs-dkms

# Import pool on boot
install -D -m 644 /setup/images/plasmon/import-pool.service /etc/systemd/system/import-pool.service
systemctl daemon-reload
systemctl enable import-pool

# Run docker out of a tmpfs for performance
cat >> /etc/fstab <<-EOF
	tmpfs /var/lib/docker tmpfs size=16G,mode=0710 0 0
EOF

# Start sshd, dhcp and docker on boot
systemctl enable sshd dhcpcd docker

# Configure static pods
cp \
	/setup/ca/api-server.pem /setup/ca/api-server-key.pem \
	/setup/ca/root.pem /setup/images/plasmon/etcd.conf.yml \
	/etc/kubernetes/
cp /setup/static_pods/etcd.yaml /etc/kubernetes/manifests/
