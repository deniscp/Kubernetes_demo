#!/bin/bash
set -e
###Bootstrap cluster control-plane node, call "/root/dispatched/control-plane/join_node.sh" to join each remaining cluster node,
###add the CNI plug-in and perform cleanup.

export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir /root/dispatched/control-plane/joined/

TOKEN=$(kubeadm token generate)
CTL_PLANE_IP=$(hostname -I | grep -E -o "^([0-9]{1,3}[\.]){3}[0-9]{1,3}")

kubeadm init --pod-network-cidr "10.1.0.0/16" --token "$TOKEN" --skip-token-print
#kubeadm init --token "$TOKEN" --skip-token-print


    ###Add the CNI networking pod plug-in
echo -e "\n  [ Adding the CNI networking pod plug-in ... ]\n"
#Detect if "kubeadm init" has been invoked with --pod-network-cidr and a custom pod network address and in that case adjust the plugin file "custom-resources.yaml"
DEFAULT_POD_CIDR="192.168.0.0/16"
CUSTOM_POD_CIDR=$(kubectl cluster-info dump | grep -m 1 cluster-cidr | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}[\/][0-9]{1,2}")

if [[ ! -z "$CUSTOM_POD_CIDR" ]]; then
  echo "Detected custom Pod Network: '--pod-network-cidr $CUSTOM_POD_CIDR' provided to \"kubeadm init\""
  sed  -i 's,'"$DEFAULT_POD_CIDR"','"$CUSTOM_POD_CIDR"',g' /root/dispatched/control-plane/CNI_plugins/custom-resources.yaml
else
  echo "Detected default Pod Network: option '--pod-network-cidr' not provided to \"kubeadm init\""
fi

#Prevent NetworkManager from managing default network namespace Calico-managed interfaces
cat <<EOF | tee /etc/NetworkManager/conf.d/calico.conf
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
EOF
systemctl restart NetworkManager

echo "  --- kubectl create -f /root/dispatched/control-plane/CNI_plugins/tigera-operator.yaml"
kubectl create -f /root/dispatched/control-plane/CNI_plugins/tigera-operator.yaml
echo "  --- kubectl create -f /root/dispatched/control-plane/CNI_plugins/custom-resources.yaml"
kubectl create -f /root/dispatched/control-plane/CNI_plugins/custom-resources.yaml


    ###Join the nodes
echo -e "\n  [ Joining nodes ... ]\n"

DISCOVERY_TOKEN_CACERT_HASH="sha256:$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null |  openssl dgst -sha256 -hex | sed 's/^.* //')"

cat /root/dispatched/control-plane/join_nodes | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | xargs -I{} sh -c '"/root/dispatched/control-plane/join_node.sh" "$1" "$2" "$3" "$4" 2>&1 | tee "/root/dispatched/control-plane/joined/$1.log"'  -- {} "$CTL_PLANE_IP" "$TOKEN" "$DISCOVERY_TOKEN_CACERT_HASH"



    ####Perform cleanup
echo -e "\n  [ Performing cleanup ... ]\n"
#Remove the bidirectional-trust joining token
kubeadm token delete $TOKEN

#Remove the no longer needed "tmp_kubeadm_join.pub" key from ~/.ssh/authorized_keys
TEMP_PUB_KEY=$(cat /root/dispatched/control-plane/ssh_keys/tmp_kubeadm_join.pub | grep -E -o "^[^ ]+ [^ ]+")
sed -i 's;'"$TEMP_PUB_KEY"'.*$;;g' /root/.ssh/authorized_keys
echo "Public key \"tmp_kubeadm_join.pub\" deleted from \"/root/.ssh/authorized_keys\" on control-plane node $CTL_PLANE_IP"

#Remove the no longer needed "tmp_kubeadm_join" key pair from "/root/dispatched/control-plane/ssh_keys/"
rm /root/dispatched/control-plane/ssh_keys/tmp_kubeadm_join*
echo "Key pair \"tmp_kubeadm_join\" deleted from \"/root/dispatched/control-plane/ssh_keys/\" on control-plane node $CTL_PLANE_IP"

