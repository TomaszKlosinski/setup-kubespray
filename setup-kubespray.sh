#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

REPO_DIR=$( pwd )

# This should be equal to the server version
KUBECTL_VERSION="$( grep 'kube_version:' ./roles/download/defaults/main.yml | awk '{ print $2 }' | tr -d '\r' )"

# Use virtualenv to install all python requirements
echo -e "\nInstall Python modules"
VENVDIR=venv
virtualenv --python=python3 $VENVDIR
source $VENVDIR/bin/activate
pip install -r requirements.txt


# Prepare an inventory to test with
INV=inventory/lab
cp -a inventory/sample ${INV}


# Customize the vagrant environment
mkdir -p vagrant

cat << EOF > vagrant/config.rb
\$instance_name_prefix = "kub"
\$vm_cpus = 1
\$num_instances = 3
\$os = "ubuntu1804"
\$subnet = "10.0.20"
\$network_plugin = "flannel"
\$inventory = "$INV"
EOF


# Run Vagrant
echo -e "\n\n\nRun vagrant"
vagrant up


# Install and configure Kubernetes client (kubectl):
echo -e "\n\n\nInstall and configure kubectl"
cd $INV/artifacts
rm -rf kubectl kubectl.sh

curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/darwin/amd64/kubectl
mv kubectl kubectl-binary
chmod +x kubectl-binary

cat << EOF > kubectl.sh
#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

\${DIR}/kubectl-binary --kubeconfig=\${BASH_SOURCE%/*}/admin.conf \$@
EOF

chmod +x kubectl.sh
export PATH=$PATH:$PWD

# Verify Kubernetes client works:
echo -e "\n\n\nCheck kubectl version"
kubectl.sh version

echo -e "\n\nGet nodes in k8s cluster"
kubectl.sh get nodes

cd $REPO_DIR


# Create admin user
cd $INV

cat << EOF > service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF

echo -e "\n\nApply service-account.yaml"
kubectl.sh apply -f service-account.yaml


cat << EOF > cluster-role-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
EOF

echo -e "\n\nApply cluster-role-binding.yaml"
kubectl.sh apply -f cluster-role-binding.yaml

# Copy admin user token:
echo -e "\n\n\n#################### ADMIN TOKEN ####################"
ADMIN=$( kubectl.sh -n kube-system get secret | grep admin-user | awk '{print $1}' )
kubectl.sh -n kube-system describe secret ${ADMIN}

FIRST_MASTER=$( vagrant ssh kub-1 -c "ip address show eth1 | grep 'inet ' | sed -e 's/^.*inet //' -e 's/\/.*$//'" | tr -d '\r' 2>/dev/null )
echo -e "\n\nOpen and paste the token to login as admin:"
echo -e "\thttps://${FIRST_MASTER}:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login"

echo -e "\n\nTo use local kubectl run:"
echo -e "\t$INV/artifacts/kubectl.sh"
