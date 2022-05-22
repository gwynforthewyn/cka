#!/bin/bash -el
# kubeadm installation instructions as on
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

# this script supports centos 7 and Ubuntu 20.04 only
# run this script with sudo

if ! [ $USER = root ]
then
	echo run this script with sudo
	exit 3
fi


echo RUNNING CENTOS CONFIG
# Repo check turned off per https://cloud.google.com/compute/docs/troubleshooting/known-issues#keyexpired
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

# Set SELinux in permissive mode (effectively disabling it)
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# disable swap (assuming that the name is /dev/centos/swap
sed -i 's/^\/dev\/mapper\/centos-swap/#\/dev\/mapper\/centos-swap/' /etc/fstab
# We also disable swap in another script, and don't want this to generate an error if it's already off.
swapoff /dev/mapper/centos-swap || true

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# Set up kubelet to use the cri-dockerd runtime

systemctl enable --now kubelet

sysctl --system

echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /root/.bashrc