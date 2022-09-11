HOSTNAME=plasmon
SETUP_DIR=../.. # repo root
SETUP_EXCLUDE=../../.imageignore
IMAGE_SIZE=4GiB
PACKAGES=(
	# debugging tools
	vim
	python
	htop
	man
	# networking
	openssh
	dhcpcd
	# for zfs
	linux-headers
	# container runtime
	crictl
	containerd
	# kubelet also pulls in other required bits like cni-plugins, socat
	# and the nftables-based version of iptables.
	# This also enables net.ipv4.ip_forward.
	kubelet
)
SETUP_SCRIPT=setup.sh
