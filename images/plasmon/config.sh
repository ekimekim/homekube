HOSTNAME=plasmon
SETUP_DIR=. # repo root
IMAGE_SIZE=4GiB
PACKAGES=(
	docker
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
)
SETUP_SCRIPT=images/plasmon/setup.sh
