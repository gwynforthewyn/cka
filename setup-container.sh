#!/bin/bash
# script that runs 
# https://kubernetes.io/docs/setup/production-environment/container-runtime

# setting MYOS variable
MYOS=$(hostnamectl | awk '/Operating/ { print $3 }')
OSVERSION=$(hostnamectl | awk '/Operating/ { print $4 }')

##### CentOS 7 config
if [ $MYOS = "CentOS" ]
then
	echo setting up CentOS 7 with Docker 
	yum install -y vim yum-utils device-mapper-persistent-data lvm2
	yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

	# notice that only verified versions of Docker may be installed
	# verify the documentation to check if a more recent version is available

	yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

	[ ! -d /etc/docker ] && mkdir /etc/docker

	mkdir -p /etc/systemd/system/docker.service.d


	cat > /etc/docker/daemon.json <<- EOF
	{
	  "exec-opts": ["native.cgroupdriver=systemd"],
	  "log-driver": "json-file",
	  "log-opts": {
	    "max-size": "100m"
	  },
	  "storage-driver": "overlay2",
	  "storage-opts": [
	    "overlay2.override_kernel_check=true"
	  ]
	}

	EOF

# Starting in version 1.24, I have been getting an error from kubeadm. The error is:
# # kubeadm init --apiserver-advertise-address 192.168.56.110
# [init] Using Kubernetes version: v1.24.0
# [preflight] Running pre-flight checks
# error execution phase preflight: [preflight] Some fatal errors occurred:
#	[ERROR CRI]: container runtime is not running: output: time="2022-05-18T03:00:30Z" level=fatal msg="getting status of runtime: rpc error: code = Unimplemented desc = unknown service runtime.v1alpha2.RuntimeService"
#, error: exit status 1
# I looked at installing the docker Mirantis tooling and it seemed like a pain, so let's try containerd instead.
# To use containerd, we need to install the yum packets above, and then make sure that 'cri' is not a disabled container runtime.
	sed -i 's/disabled_plugins = \["cri"]/disabled_plugins = [""]/' /etc/containerd/config.toml

	systemctl daemon-reload
	systemctl restart docker
	systemctl enable docker

	systemctl disable --now firewalld
fi

echo printing MYOS $MYOS

if [ $MYOS = "Ubuntu" ]
then
	### setting up container runtime prereq
	cat <<- EOF | sudo tee /etc/modules-load.d/containerd.conf
	overlay
	br_netfilter
	EOF

	sudo modprobe overlay
	sudo modprobe br_netfilter

	# Setup required sysctl params, these persist across reboots.
	cat <<- EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
	net.bridge.bridge-nf-call-iptables  = 1
	net.ipv4.ip_forward                 = 1
	net.bridge.bridge-nf-call-ip6tables = 1
	EOF

	# Apply sysctl params without reboot
	sudo sysctl --system

	# (Install containerd)
	sudo apt-get update && sudo apt-get install -y containerd
	# Configure containerd
	sudo mkdir -p /etc/containerd
	containerd config default | sudo tee /etc/containerd/config.toml
	# Restart containerd
	sudo systemctl restart containerd	
fi

