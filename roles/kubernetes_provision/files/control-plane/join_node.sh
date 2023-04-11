#!/bin/bash
set -e

###Join to the cluster the remaining nodes and perform cleanup

NODE_IP=$1
CTL_PLANE_IP=$2
TOKEN=$3
DISCOVERY_TOKEN_CACERT_HASH=$4

TMP_IDENTITY_FILE="/root/dispatched/control-plane/ssh_keys/tmp_kubeadm_join"
NODE_EXIT_STATUS_FILE="/root/dispatched/cluster-node/node_exit-status.log"
USER_KNOWN_HOSTS_FILE=/dev/null
STRICT_HOST_KEY_CHECKING=no

# Wait for the joining node to complete the bootstrap process
while : ; do
  NODE_READY=$(ssh -o UserKnownHostsFile="$USER_KNOWN_HOSTS_FILE" -o StrictHostKeyChecking=$STRICT_HOST_KEY_CHECKING -i "$TMP_IDENTITY_FILE" root@"$NODE_IP" /bin/bash -c "'if [[ -f $NODE_EXIT_STATUS_FILE ]]; then cat $NODE_EXIT_STATUS_FILE; fi'")
  [[ $NODE_READY != 0 ]] || break
  echo "   [Node $NODE_IP not ready yet...]"
  sleep 5
done


# Join the node
ssh -o UserKnownHostsFile="$USER_KNOWN_HOSTS_FILE" -o StrictHostKeyChecking=$STRICT_HOST_KEY_CHECKING -i "$TMP_IDENTITY_FILE" root@"$NODE_IP" kubeadm join "$CTL_PLANE_IP:6443" --token "$TOKEN"   --discovery-token-ca-cert-hash "$DISCOVERY_TOKEN_CACERT_HASH"

echo "Joined $NODE_IP" | tee -a /root/dispatched/control-plane/joined/joined.txt

#Remove the no-longer-needed "tmp_kubeadm_join.pub" key from /root/.ssh/authorized_keys
TEMP_PUB_KEY=$(cat /root/dispatched/control-plane/ssh_keys/tmp_kubeadm_join.pub | grep -E -o "^[^ ]+ [^ ]+")
ssh -o UserKnownHostsFile="$USER_KNOWN_HOSTS_FILE" -o StrictHostKeyChecking=$STRICT_HOST_KEY_CHECKING -i "$TMP_IDENTITY_FILE" root@"$NODE_IP" "sed    -i 's;'\""$TEMP_PUB_KEY"\"'.*$;;g' /root/.ssh/authorized_keys"
echo "Public key \"tmp_kubeadm_join.pub\" deleted from \"/root/.ssh/authorized_keys\" on worker node $NODE_IP"

exit 0
