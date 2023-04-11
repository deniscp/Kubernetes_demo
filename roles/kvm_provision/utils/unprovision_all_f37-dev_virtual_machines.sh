#!/bin/bash
###Utility to unprovision VMPATTERN prefixed VMs removing their associated images and exernal storages

VMPATTERN="f37-dev" #Virtual machine name prefix to purge

VMs=$(virsh list --all | grep -o -E "($VMPATTERN\S*)")
echo -e "VMs $VMPATTERN* found:\n$VMs\n"

echo "$VMs" | xargs -I % sh -c 'virsh destroy --domain %'
RESULT=$((echo "$VMs" | xargs -I % sh -c 'virsh undefine --remove-all-storage --domain %' ) 2>&1)

echo "$RESULT"

REMOVE_MANUALLY='Remove it manually'
if [[ "$RESULT" == *"$REMOVE_MANUALLY"* ]]; then
  echo "$VMs" | xargs -I % sudo rm -v /var/lib/libvirt/images/%.qcow2
fi
