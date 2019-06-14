# setup-kubespray
A script to configure local [Kubernetes](https://kubernetes.io/) cluster using [Kubespray](https://github.com/kubernetes-sigs/kubespray/) on [Vagrant](https://www.vagrantup.com/)/[Virtualbox](https://www.virtualbox.org/)


## Installation
Clone kubespray repo:
```
git clone git@github.com:kubernetes-sigs/kubespray.git
cd kubespray
```

Optionally, set the kubespray version:
```
git checkout v2.10.3
```

Download and run setup-kubespray.sh
```
curl -LO https://raw.githubusercontent.com/TomaszKlosinski/setup-kubespray/master/setup-kubespray.sh
chmod +x setup-kubespray.sh
./setup-kubespray.sh
```
The script will produce an admin token to access the dashboard.  
Please copy it and paste into:  
https://10.0.20.101:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login


To use local kubectl run:
```
./inventory/lab/artifacts/kubectl.sh [command]
```

---

To kill the cluster:
```
vagrant destroy --force
```
