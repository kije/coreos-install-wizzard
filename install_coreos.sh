#!/bin/bash
#
# The MIT License (MIT)
# 
# Copyright (c) 2015 Kim Jeker
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE. 
#


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



indent_line() {
	local stdin_val=0
	local indentation_level=$1
	local indentation_str=$(printf "%${indentation_level}s%${indentation_level}s")
	while IFS= read -r line; do
	  echo $line | awk "\$0=\"$indentation_str\"\$0"
	done
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
	echo "#cloud-config" | indent_line 0 > $CLOUD_CONFIG_FILE_PATH
	echo "" >> $CLOUD_CONFIG_FILE_PATH

	# users
	echo "Create user ..."
	echo "Enter Username: "
	read USERNAME

	echo "Setup password for user $USERNAME:"
	PASSWORD=$(openssl passwd -1)

	echo "users:" | indent_line 0 >> $CLOUD_CONFIG_FILE_PATH
	echo "- name: $USERNAME" | indent_line 1 >> $CLOUD_CONFIG_FILE_PATH
	printf "passwd: %s\n" $PASSWORD | indent_line 2 >> $CLOUD_CONFIG_FILE_PATH
	echo "groups:" | indent_line 2 >> $CLOUD_CONFIG_FILE_PATH
	echo "- sudo" | indent_line 3 >> $CLOUD_CONFIG_FILE_PATH
	echo "- docker" | indent_line 3 >> $CLOUD_CONFIG_FILE_PATH


	# network setup
	echo "setup network"

	echo "enter your domain: "
	read DOMAIN

	echo "enter hostname: "
	read HOSTNAME
	printf "hostname: \"%s\"\n" $HOSTNAME | indent_line 0 >> $CLOUD_CONFIG_FILE_PATH


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

	echo "coreos:" | indent_line 0 >> $CLOUD_CONFIG_FILE_PATH
	echo "units:" | indent_line 1 >> $CLOUD_CONFIG_FILE_PATH
	
	echo "- name: systemd-networkd.service" | indent_line 2 >> $CLOUD_CONFIG_FILE_PATH
	echo "command: stop" | indent_line 3 >> $CLOUD_CONFIG_FILE_PATH
	
	echo "- name: 00-eth0.network" | indent_line 2 >> $CLOUD_CONFIG_FILE_PATH
	echo "runtime: true" | indent_line 3 >> $CLOUD_CONFIG_FILE_PATH
	echo "content: |" | indent_line 3 >> $CLOUD_CONFIG_FILE_PATH
	printf "$nework_unit_content\n" | indent_line 4 >> $CLOUD_CONFIG_FILE_PATH 
	
	echo "- name: down-interfaces.service" | indent_line 2 >> $CLOUD_CONFIG_FILE_PATH
	echo "command: start" | indent_line 3 >> $CLOUD_CONFIG_FILE_PATH
	echo "content: |" | indent_line 3 >> $CLOUD_CONFIG_FILE_PATH
	echo "[Service]
Type=oneshot
ExecStart=/usr/bin/ip link set eth0 down
ExecStart=/usr/bin/ip addr flush dev eth0" | indent_line 4 >> $CLOUD_CONFIG_FILE_PATH
	
	echo "- name: systemd-networkd.service" | indent_line 2 >> $CLOUD_CONFIG_FILE_PATH
	echo "command: restart" | indent_line 3 >> $CLOUD_CONFIG_FILE_PATH




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

	# todo let the user choose the version of coreos (version, install type, chanel, etc...) and where to install
	echo "start installation"
	$COREOS_INSTALL_SCRIPT_PATH -d /dev/sda -V current -C stable  -c $CLOUD_CONFIG_FILE_PATH

else
	echo "aborting..."
fi





# clean up
echo "cleaning up..."
cd ..
rm -r $TMP_DIR_PATH