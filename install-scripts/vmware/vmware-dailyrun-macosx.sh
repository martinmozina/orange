#!/bin/bash -e
#
# Should be run as: ./wmvare-dailyrun-macosx.sh [bundle only]
#
# If [bundle only] is given it only builds the bundle
#

VMRUN='/Library/Application Support/VMware Fusion/vmrun'
VMIMAGE='/Users/ailabc/Documents/Virtual Machines.localized/Mac OS X Server 10.5 64-bit.vmwarevm/Mac OS X Server 10.5 64-bit.vmx'
WAIT_TIME=300
RETRIES=5
IP_ADDRESS='172.16.213.100'
NAME='Mac OS X'

if [ "$1" ]; then
	BUNDLE_ONLY=1
fi

# Sets error handler
trap "echo \"Script failed\"" ERR

# We use public/private keys SSH authentication so no need for a password

start_vmware() {
	if "$VMRUN" list | grep -q "$VMIMAGE"; then
		echo "[$NAME] VMware is already running."
		exit 1
	fi
	
	# We hide some Mac OS X warnings which happen if nobody is logged into a host Mac OS X
	set +e
	"$VMRUN" start "$VMIMAGE" nogui 2>&1 | grep -i -v 'Untrusted apps are not allowed to connect to or launch Window Server before login' | grep -i -v 'FAILED TO establish the default connection to the WindowServer'
	ps=("${PIPESTATUS[@]}")
	set -e
	# PIPESTATUS check is needed so that we test return value of the VMRUN and not grep
	if ((${ps[0]})); then false; fi
	
	# Wait for VMware and OS to start
	sleep $WAIT_TIME
	
	return 0
}

stop_vmware() {
	# shutdown is added to /etc/sudoers so no password is required
	# /etc/sudoers entry: ailabc ALL=NOPASSWD:/sbin/shutdown -h now
	ssh ailabc@$IP_ADDRESS "sudo /sbin/shutdown -h now > /dev/null"
	
	# Wait for OS to stop
	sleep $WAIT_TIME
	
	if "$VMRUN" list | grep -q "$VMIMAGE"; then
		echo "[$NAME] Had to force shutdown."
		# We hide some Mac OS X warnings which happen if nobody is logged into a host Mac OS X
		set +e
		"$VMRUN" stop "$VMIMAGE" nogui 2>&1 | grep -i -v 'Untrusted apps are not allowed to connect to or launch Window Server before login' | grep -i -v 'FAILED TO establish the default connection to the WindowServer' | true
		ps=("${PIPESTATUS[@]}")
		set -e
		# PIPESTATUS check is needed so that we test return value of the VMRUN and not grep
		if ((${ps[0]})); then false; fi
	fi
	
	return 0
}

start_vmware

# Check if autologin was successful
for LOGGED_IN in {1..$RETRIES}; do
	if ssh ailabc@$IP_ADDRESS "who | grep -q console"; then
		# Autologin was successful
		break
	fi
	
	stop_vmware
	
	# Wait for VMware to stop
	sleep $WAIT_TIME
	
	start_vmware
done

if ! ssh ailabc@$IP_ADDRESS "who | grep -q console"; then
	# Autologin was not successful after few retries, give up
	echo "[$NAME] Could not autologin."
	stop_vmware
	exit 2
fi

# We run it twice so that we als use maybe updated "update-all-scripts.sh" script
ssh ailabc@$IP_ADDRESS "/Users/ailabc/update-all-scripts.sh"
ssh ailabc@$IP_ADDRESS "/Users/ailabc/update-all-scripts.sh"

if [ $BUNDLE_ONLY ]; then
	# dailyrun-bundleonly.sh is added to /etc/sudoers so no password is required
	# /etc/sudoers entry: ailabc ALL=NOPASSWD:/Users/ailabc/dailyrun-bundleonly.sh
	# WARNING: This is generally insecure as an attacker could change dailyrun-bundleonly.sh file and ...
	#          but we are using it in a VMware which is used only for this script, so ...
	ssh ailabc@$IP_ADDRESS "sudo /Users/ailabc/dailyrun-bundleonly.sh"
else
	# dailyrun.sh is added to /etc/sudoers so no password is required
	# /etc/sudoers entry: ailabc ALL=NOPASSWD:/Users/ailabc/dailyrun.sh
	# WARNING: This is generally insecure as an attacker could change dailyrun.sh file and ...
	#          but we are using it in a VMware which is used only for this script, so ...
	ssh ailabc@$IP_ADDRESS "sudo /Users/ailabc/dailyrun.sh"
fi

stop_vmware
