#!/bin/bash
set -e

### Create a new user account, generate a kubeconfig file with permission on a limited set of resources and on a single namespace
### and use the genereated account to deploy a demo app.

USR_NAME="developer"
USR_ROLE="devops"
USR_HOME_DIR="/home/developer"
USR_KEYS_DIR="$USR_HOME_DIR/keys"

useradd -m -d "$USR_HOME_DIR" "$USR_NAME"

echo "developer:test123" | chpasswd

mkdir "$USR_KEYS_DIR"

USR_PRV_KEY="$USR_KEYS_DIR/$USR_NAME.key"
USR_CSR="$USR_KEYS_DIR/$USR_NAME.csr"
USR_CRT="$USR_KEYS_DIR/$USR_NAME.crt"
USR_KUBECONFIG_FILE="$USR_KEYS_DIR/$USR_NAME-kubeconfig.config"
USR_CSR_MANIFEST_FILE="$USR_KEYS_DIR/csr_manifest.yaml"
USR_CLUSTER_NAMESPACE="$USR_ROLE"


openssl req -new -newkey rsa:2048 -noenc -keyout "$USR_PRV_KEY" -out $USR_CSR -subj "/CN=$USR_NAME/O=$USR_ROLE"

###Build the CSR yaml manifest file
cat <<EOF | tee $USR_CSR_MANIFEST_FILE
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
EOF
echo "  name: $USR_NAME" | tee -a $USR_CSR_MANIFEST_FILE
echo "spec:" | tee -a $USR_CSR_MANIFEST_FILE
echo "  request: $(cat $USR_CSR | base64 | tr -d '\n')" | tee -a $USR_CSR_MANIFEST_FILE
cat <<EOF | tee -a $USR_CSR_MANIFEST_FILE
  signerName: kubernetes.io/kube-apiserver-client
  #expirationSeconds: 86400  # one day
  usages:
  - client auth
EOF

export KUBECONFIG=/etc/kubernetes/admin.conf

attempts=0
while : ; do
  CLUSTER_READY=$(kubectl wait  --all pods --for=condition=Ready -A 2>&1 | { grep -v "condition met" || true; })
  [[ ! -z $CLUSTER_READY ]] || break
  echo -e "\n   [ Cluster not ready yet... ] $((++attempts))\n$CLUSTER_READY"
  sleep 5
done

echo -e "\n   [ Cluster is now ready  ] $((++attempts))"

kubectl apply -f $USR_CSR_MANIFEST_FILE

kubectl certificate approve "$USR_NAME"

attempts=0
while : ; do
  kubectl get csr "$USR_NAME" -o jsonpath='{.status.certificate}'| base64 -d > $USR_CRT
  USR_CRT_AVAILABLE=$(tail -n1 $USR_CRT | { grep -c -- "-----END CERTIFICATE-----" || true; })
  [[ $USR_CRT_AVAILABLE != 1 ]] || break
  echo -e "\n   [ User certificate not ready yet... ] $((++attempts))"
  sleep 5
done

echo -e "\n   [ User certificate is now ready ] $((++attempts))"


kubectl create ns $USR_CLUSTER_NAMESPACE

kubectl create role $USR_ROLE --namespace="$USR_CLUSTER_NAMESPACE" --verb=create,get,list,update,delete,watch,patch --resource=pods,deployments,secrets,configmaps,services

kubectl create rolebinding "$USR_ROLE-binding-$USR_NAME" --namespace="$USR_CLUSTER_NAMESPACE" --role="$USR_ROLE" --user="$USR_NAME"


kubectl config set-cluster $(kubectl config view -o jsonpath='{.clusters[0].name}') --server="$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')" --certificate-authority="/etc/kubernetes/pki/ca.crt" --embed-certs=true --kubeconfig="$USR_KUBECONFIG_FILE"

kubectl config set-credentials "$USR_NAME" --client-certificate="$USR_CRT" --client-key="$USR_PRV_KEY" --embed-certs=true --kubeconfig="$USR_KUBECONFIG_FILE"

kubectl config set-context "$USR_NAME@$(kubectl config view -o jsonpath='{.clusters[0].name}')" --cluster=$(kubectl config view -o jsonpath='{.clusters[0].name}') --namespace="$USR_CLUSTER_NAMESPACE" --user="$USR_NAME" --kubeconfig="$USR_KUBECONFIG_FILE"

kubectl config use-context "$USR_NAME@$(kubectl config view -o jsonpath='{.clusters[0].name}')" --kubeconfig="$USR_KUBECONFIG_FILE"

chown -R "$USR_NAME:$USR_NAME" "$USR_KEYS_DIR"

sudo -u "$USR_NAME" mkdir "$USR_HOME_DIR/.kube/"
sudo -u "$USR_NAME" cp "$USR_KUBECONFIG_FILE" "$USR_HOME_DIR/.kube/config"


# Deploy the demo app as the new created user
unset KUBECONFIG

mv /root/dispatched/user/demo "$USR_HOME_DIR/"

export USR_DEMO_DIR="$USR_HOME_DIR/demo"

chown $USR_NAME:$USR_NAME -R $USR_DEMO_DIR

su --whitelist-environment=USR_DEMO_DIR - $USR_NAME -c "cd $USR_DEMO_DIR && ./deployment.sh 1>> deployment_stdout.log 2>> deployment_stderr.log"
