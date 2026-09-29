#!/usr/bin/env bash
#
# Removes Docker Engine from an Ubuntu host and installs containerd + kubeadm/kubelet/kubectl
# for Kubernetes v1.37, following the upstream Kubernetes (LFX) and containerd documentation:
#   https://kubernetes.io/docs/setup/production-environment/container-runtimes/
#   https://kubernetes.io/docs/tasks/tools/install-kubeadm/
#   https://docs.docker.com/engine/install/ubuntu/#uninstall-docker-engine
#
# Tested target: Ubuntu 22.04/24.04 LTS. Run as root (or via sudo) on each node.

set -euo pipefail

K8S_VERSION="1.37"                 # kubeadm/kubelet/kubectl minor version line (pkgs.k8s.io repo)
K8S_PKG_VERSION="1.37.0-1.1"       # exact package version to pin, adjust if repo revision differs
CONTAINERD_VERSION=""              # empty = latest available from Docker's apt repo

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# 1. Remove Docker Engine and related packages
# ---------------------------------------------------------------------------
log "Removing Docker packages"
docker_pkgs=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker
             docker-ce docker-ce-cli docker-ce-rootless-extras docker-buildx-plugin
             docker-compose-plugin containerd runc)
apt-get purge -y "${docker_pkgs[@]}" || true
apt-get autoremove -y --purge || true

log "Cleaning up Docker data and config"
rm -rf /var/lib/docker
rm -rf /var/lib/containerd
rm -rf /etc/docker
rm -rf /etc/containerd
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/keyrings/docker.asc
getent group docker >/dev/null && groupdel docker || true

# ---------------------------------------------------------------------------
# 2. Kernel prerequisites for container networking
# ---------------------------------------------------------------------------
log "Configuring kernel modules and sysctl for Kubernetes networking"
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                = 1
EOF
sysctl --system

log "Disabling swap"
swapoff -a
sed -ri 's/^([^#].*\sswap\s.*)$/#\1/' /etc/fstab

# ---------------------------------------------------------------------------
# 3. Install containerd from Docker's apt repository
# ---------------------------------------------------------------------------
log "Installing prerequisite packages"
apt-get update
apt-get install -y ca-certificates curl gnupg apt-transport-https

log "Adding Docker apt repository (source of the containerd.io package)"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# shellcheck disable=SC1091
. /etc/os-release
cat <<EOF | tee /etc/apt/sources.list.d/docker.list
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable
EOF

apt-get update
if [[ -n "$CONTAINERD_VERSION" ]]; then
  apt-get install -y "containerd.io=${CONTAINERD_VERSION}"
else
  apt-get install -y containerd.io
fi

log "Configuring containerd (SystemdCgroup driver)"
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable containerd
systemctl restart containerd

# ---------------------------------------------------------------------------
# 4. Install kubeadm, kubelet, kubectl
# ---------------------------------------------------------------------------
log "Adding Kubernetes v${K8S_VERSION} apt repository"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  -o /etc/apt/keyrings/kubernetes-apt-keyring.asc
chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.asc

cat <<EOF | tee /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.asc] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /
EOF

apt-get update
if apt-cache madison kubeadm | grep -q "${K8S_PKG_VERSION}"; then
  apt-get install -y kubelet="${K8S_PKG_VERSION}" kubeadm="${K8S_PKG_VERSION}" kubectl="${K8S_PKG_VERSION}"
else
  log "Exact package version ${K8S_PKG_VERSION} not found, installing latest v${K8S_VERSION}.x instead"
  apt-get install -y kubelet kubeadm kubectl
fi
apt-mark hold kubelet kubeadm kubectl

systemctl enable --now kubelet

log "Done. containerd + kubeadm/kubelet/kubectl (v${K8S_VERSION}) are installed."
log "Next steps: run 'kubeadm init ...' on the control-plane node, or 'kubeadm join ...' on workers."
