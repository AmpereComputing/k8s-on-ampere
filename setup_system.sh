#!/usr/bin/env bash
set -o errexit
set -o nounset



# install pre-reqs
sudo apt-get update && sudo apt-get -y upgrade && sudo apt install -y curl 

# install Kubernetes:
sudo bash -c "cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial-unstable main
EOF"
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt update && sudo apt install -y kubelet kubeadm kubectl

# install containerd
sudo apt install -y containerd
sudo systemctl start containerd

# host configuration adjustments for running Kubernetes:
sudo swapoff -a
sudo modprobe br_netfilter
echo 1 | sudo tee -a /proc/sys/net/ipv4/ip_forward > /dev/null
