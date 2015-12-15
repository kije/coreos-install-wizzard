#!/bin/bash
 
TMP_DIR_PATH="$(readlink -f .)/coreos_install"
COREOS_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/coreos/init/master/bin/coreos-install"
COREOS_INSTALL_SCRIPT_NAME="coreos-install"
COREOS_INSTALL_SCRIPT_PATH="$TMP_DIR_PATH/$COREOS_INSTALL_SCRIPT_NAME"
CLOUD_CONFIG_FILE_PATH="$TMP_DIR_PATH/cloud-config-file"


# functions
function ask_user_yes_no {
	local repeate_step=1
	local user_answer=""
	local return_val=0

	while [ $repeate_step -eq 1 ]
	do
		echo "$1 (y/n) "
		read user_answer

		if [ "$user_answer" == "y" ];
			then
			return_val=1
			repeate_step=0
		elif [ $user_answer == "n" ];
			then
			return_val=0
			repeate_step=0
		else
			echo "Unrecognized answer. Please enter y or n!"
			repeate_step=1
		fi
	done

	return $return_val
}


# check if root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi


# prepare
echo "prepare install..."
mkdir $TMP_DIR_PATH
cd $TMP_DIR_PATH

# download core os install script
echo "downloading coreos-install"
wget $COREOS_INSTALL_SCRIPT_URL -O $COREOS_INSTALL_SCRIPT_NAME
chmod +x $COREOS_INSTALL_SCRIPT_PATH


ask_user_yes_no "do you want to configure this coreos installation with the wizzard (y), or do you want to provide a custom cloud-config file (n)?"
user_wants_wizzard=$?

if [ $user_wants_wizzard -eq 1 ];
	then
	# create cloudinit file
	echo "#cloud-config" > $CLOUD_CONFIG_FILE_PATH
	echo "" >> $CLOUD_CONFIG_FILE_PATH

	# users
	echo "Create user ..."
	echo "Enter Username: "
	read USERNAME

	echo "Setup password for user $USERNAME:"
	PASSWORD=$(openssl passwd -1)

	echo "users:" >> $CLOUD_CONFIG_FILE_PATH
	echo "  - name: $USERNAME" >> $CLOUD_CONFIG_FILE_PATH
	echo "    passwd: $PASSWORD" >> $CLOUD_CONFIG_FILE_PATH
	echo "    groups:" >> $CLOUD_CONFIG_FILE_PATH
	echo "      - sudo" >> $CLOUD_CONFIG_FILE_PATH
	echo "      - docker" >> $CLOUD_CONFIG_FILE_PATH


	# network setup
	echo "setup network"

	echo "enter your domain: "
	read DOMAIN

	echo "enter hostname: "
	read HOSTNAME
	echo "hostname: \"$HOSTNAME\"" >> $CLOUD_CONFIG_FILE_PATH


	nework_unit_content=""

	# see https://coreos.com/os/docs/latest/network-config-with-networkd.html
	# ipv4
	echo "enter this machines ipv4 address: "
	read IPV4_ADDR

	echo "enter the network (ipv4) CIDR: "
	read IPV4_CIDR

	echo "enter the network (ipv4) gateway: "
	read IPV4_GATEWAY

	echo "enter the network (ipv4) dns: "
	read IPV4_DNS


	nework_unit_content="[Match]
Name=eth0

[Network]
DNS=${IPV4_DNS}
Address=${IPV4_ADDR}/${IPV4_CIDR}
Gateway=${IPV4_GATEWAY}"

	ask_user_yes_no "do you also want to setup IPv6 network?"
	user_wants_ipv6=$?

	if [ $user_wants_ipv6 -eq 1 ];
		then
		# ipv6
		echo "enter this machines ipv6 address: "
		read IPV6_ADDR

		echo "enter the network (ipv6) prefix length: "
		read IPV6_CIDR

		echo "enter the network (ipv6) gateway: "
		read IPV6_GATEWAY

		nework_unit_content="$nework_unit_content
Address=${IPV6_ADDR}/${IPV6_CIDR}
Gateway=${IPV6_GATEWAY}"
#todo add route
	fi

	echo "coreos:" >> $CLOUD_CONFIG_FILE_PATH
	echo "  units:" >> $CLOUD_CONFIG_FILE_PATH
	echo "    - name: systemd-networkd.service" >> $CLOUD_CONFIG_FILE_PATH
	echo "      command: stop" >> $CLOUD_CONFIG_FILE_PATH
	echo "    - name: 00-eth0.network" >> $CLOUD_CONFIG_FILE_PATH
	echo "      runtime: true" >> $CLOUD_CONFIG_FILE_PATH
	echo "      content: |" >> $CLOUD_CONFIG_FILE_PATH
	printf "$nework_unit_content\n" | awk '$0="        "$0' >> $CLOUD_CONFIG_FILE_PATH  # prefixed content of file
	echo "    - name: down-interfaces.service" >> $CLOUD_CONFIG_FILE_PATH
	echo "      command: start" >> $CLOUD_CONFIG_FILE_PATH
	echo "      content: |" >> $CLOUD_CONFIG_FILE_PATH
	echo "        [Service]" >> $CLOUD_CONFIG_FILE_PATH
	echo "        Type=oneshot" >> $CLOUD_CONFIG_FILE_PATH
	echo "        ExecStart=/usr/bin/ip link set eth0 down" >> $CLOUD_CONFIG_FILE_PATH
	echo "        ExecStart=/usr/bin/ip addr flush dev eth0" >> $CLOUD_CONFIG_FILE_PATH
	echo "    - name: systemd-networkd.service" >> $CLOUD_CONFIG_FILE_PATH
	echo "      command: restart" >> $CLOUD_CONFIG_FILE_PATH



	# todo ssh config!

	# ectd config
	# get token: https://discovery.etcd.io/new?size=1
else
	echo "enter the path to your custom cloud-config file: "
	read custom_cloud_config_file_path

	cp $custom_cloud_config_file_path $CLOUD_CONFIG_FILE_PATH
fi



echo 
echo "Here is your cloud-config that will be installed: "
cat $CLOUD_CONFIG_FILE_PATH
echo

if hash coreos-cloudinit 2>/dev/null; then
	echo "validating cloud-config..."
	coreos-cloudinit -validate=true -from-file=$CLOUD_CONFIG_FILE_PATH
fi

#todo provide user with ability to edit file (using vim) nad revalidating it after that again


ask_user_yes_no "Would you like to proceed with the instalation?"
user_wants_installation=$?


if [ $user_wants_installation -eq 1 ];
	then
	# install

	# todo let the user choose the version of coreos (version, install type, chanel, etc...) to install
	echo "start instalation"
	$COREOS_INSTALL_SCRIPT_PATH -d /dev/sda -V current -C stable  -c $CLOUD_CONFIG_FILE_PATH

else
	echo "aborting..."
fi





# clean up
echo "cleaning up..."
cd ..
rm -r $TMP_DIR_PATH