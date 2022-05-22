#!/bin/bash -el
# script that runs 
# https://kubernetes.io/docs/setup/production-environment/container-runtimes

# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#forwarding-ipv4-and-letting-iptables-see-bridged-traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
	overlay
	br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sysctl --system
# /https://kubernetes.io/docs/setup/production-environment/container-runtimes/#forwarding-ipv4-and-letting-iptables-see-bridged-traffic

# The next section is https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroup-drivers
# This is configuring the cgroup driver. This is accomplished with the setting "native.cgroupdriver=systemd"
# when it is handed into docker via daemon.json below.


# The next section is CRI Runtimes.
# We are going to use 
# The container-runtimes article points to https://github.com/containerd/containerd/blob/main/docs/getting-started.md
# to set up docker-engine, so we can use docker images.

# First install docker-engine.
# Then install cri-dockerd.
echo setting up CentOS 7 with Docker\-Engine 
echo "Instructions at https://docs.docker.com/engine/install/#server"
yum install -y vim yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# notice that only verified versions of Docker may be installed
# verify the documentation to check if a more recent version is available
yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl daemon-reload
systemctl enable --now containerd


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

systemctl enable docker
systemctl start docker

# We need to manually install dockershim, which is now called cri-dockerd.
# https://github.com/Mirantis/cri-dockerd

# To do that, we need wget to install golang, git to get the go code for cri-dockerd and golang.
# Let's fetch those up here
yum install -y wget git 
echo 'export GOPATH=/root/golang/' >> /root/.bash_profile
echo 'export GOPATH=/home/vagrant/golang/' >> /vagrant/.bash_profile

echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bash_profile
echo 'export PATH=$PATH:/usr/local/go/bin' >> /vagrant/.bash_profile

source /root/.bash_profile

wget https://dl.google.com/go/go1.13.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.13.linux-amd64.tar.gz

git clone https://github.com/Mirantis/cri-dockerd.git
cd cri-dockerd/src && go get && go build -o ../bin/cri-dockerd

cd ..

install -o root -g root -m 0755 bin/cri-dockerd /usr/local/bin/cri-dockerd
cp -a packaging/systemd/* /etc/systemd/system
sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
systemctl daemon-reload
systemctl enable cri-docker.service
systemctl enable --now cri-docker.socket

systemctl restart containerd
systemctl restart docker

systemctl disable --now firewalld
