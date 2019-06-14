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
\$network_plugin = "calico"
\$inventory = "$INV"
EOF


# Run Vagrant
echo -e "\n\n\nRun vagrant"
vagrant up


# Install and configure Kubernetes client (kubectl):
echo -e "\n\n\nInstall and configure kubectl"
cd $INV/artifacts
rm -rf kubectl kubectl.sh

if [ ! -f kubectl-binary ]; then
  echo -e "\n Download kubectl binary"
  curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/darwin/amd64/kubectl
  mv kubectl kubectl-binary
  chmod +x kubectl-binary
fi


cat << EOF > kubectl.sh
#!/bin/bash

\${BASH_SOURCE%/*}/kubectl-binary --kubeconfig=\${BASH_SOURCE%/*}/admin.conf \$@
EOF

chmod +x kubectl.sh
export PATH=$PATH:$PWD

# Verify Kubernetes client works:
echo -e "\n\n\nCheck kubectl version"
kubectl.sh version

echo -e "\n\nGet nodes of k8s cluster"
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

echo -e "\n\nApply $INV/service-account.yaml"
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

echo -e "\n\nApply $INV/cluster-role-binding.yaml"
kubectl.sh apply -f cluster-role-binding.yaml

# Copy admin user token:
echo -e "\n\n\n#################### DASHBOARD ####################"
ADMIN=$( kubectl.sh -n kube-system get secret | grep admin-user | awk '{print $1}' )
kubectl.sh -n kube-system describe secret ${ADMIN}

FIRST_MASTER=$( vagrant ssh kub-1 -c "ip address show eth1 | grep 'inet ' | sed -e 's/^.*inet //' -e 's/\/.*$//'" | tr -d '\r' 2>/dev/null )
echo -e "\n\nOpen and paste the token to login as admin:"
echo -e "\thttps://${FIRST_MASTER}:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login"


# Configure kubectl on the first master
echo -e "\n\n\n#################### KUBECTL ####################"
vagrant ssh kub-1 -c "mkdir -p ~/.kube/" > /dev/null 2>&1
vagrant ssh kub-1 -c "sudo cp /etc/kubernetes/admin.conf ~/.kube/config" > /dev/null 2>&1
vagrant ssh kub-1 -c "sudo chown vagrant:vagrant ~/.kube/config" > /dev/null 2>&1
vagrant ssh kub-1 -c "kubectl version" > /dev/null 2>&1

echo -e "\nTo access the cluster, ssh to the first master and use kubectl there:"
echo -e "\tvagrant ssh kub-1"

echo -e "\n\nAlternatively, use local kubectl:"
echo -e "\t$INV/artifacts/kubectl.sh"

echo -e "\nOr set kubectl to access this cluster pernamently:"
echo -e "\tcp $INV/artifacts/kubectl-binary /usr/local/bin/kubectl (or brew install kubernetes-cli)"
echo -e "\tln -s \$( pwd )/$INV/artifacts/admin.conf ~/.kube/config"
