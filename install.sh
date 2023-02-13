## Install Multipass

Install multipass using https://multipass.run/

## create cloud-init directory

mkdir cloud-init

## create a fie k3s. yaml

cat <<EOF >k3s.yaml
  - curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.24.7+k3s1 sh -
  - mkdir -p /home/ubuntu/.kube/
  - cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  - chown ubuntu:ubuntu /home/ubuntu/.kube/config
  - k3s completion bash > /etc/bash_completion.d/k3s
  - echo "export KUBECONFIG=/home/ubuntu/.kube/config" | tee -a /home/ubuntu/.bashrc
  - echo "alias k=\'kubectl\'" | tee -a /home/ubuntu/.bashrc
  - sudo apt install jq -y

  - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  - helm completion bash > /etc/bash_completion.d/helm
  - runuser -l ubuntu -c "helm repo add hashicorp https://helm.releases.hashicorp.com"

  - kubectl completion bash > /etc/bash_completion.d/kubectl
  - curl -sL "https://releases.hashicorp.com/vault-k8s/1.1.0/vault-k8s_1.1.0_linux_$( [ $(uname -m) = aarch64 ] && echo arm64 || echo amd64).zip" | zcat > /usr/local/bin/vault-k8s
  - chmod +x /usr/local/bin/vault-k8s
EOF

## Spin up a kubernetes cluster

multipass launch -n k3s-au -m 4G -c 2 -d 10GB --cloud-init cloud-init/k3s.yaml

## SSH into multipass vm 

multipass shell k3s-au

## Install helm

sudo snap install helm --classic

## add helm repository

helm repo add hashicorp https://helm.releases.hashicorp.com



## create values.yaml

cat <<EOF >values.yaml
server:
  affinity: ""
  ha:
    enabled: true
    raft:
      enabled: true
ui:
  # True if you want to create a Service entry for the Vault UI.
  #
  # serviceType can be used to control the type of service created. For
  # example, setting this to "LoadBalancer" will create an external load
  # balancer (for supported K8S installations) to access the UI.
  enabled: true
  publishNotReadyAddresses: true
  # The service should only contain selectors for active Vault pod
  activeVaultPodOnly: false
  serviceType: "LoadBalancer"
  serviceNodePort: null
  externalPort: 8200
  targetPort: 8200
EOF

## check the chart and helm version available

helm search repo hashicorp/vault -l | head -n 5

## install vault 

helm install consul hashicorp/vault -f values.yaml --version 0.23.0 --wait --debug

## Following this vault HA cluster should be up and running

k get pods
NAME                                           READY   STATUS    RESTARTS   AGE
consul-vault-agent-injector-6d8fff6c9f-2ckjl   1/1     Running   0          45s
consul-vault-0                                 0/1     Running   0          45s
consul-vault-2                                 0/1     Running   0          45s
consul-vault-1                                 0/1     Running   0          45s

## SSH into vault node

k exec --stdin --tty consul-vault-0 -- /bin/sh

## Come out and in ubuntu Initialise vault 

k exec -it consul-vault-0 -- vault operator init -key-shares=1 -key-threshold=1 >keys.txt

## Unseal vault

k exec -it consul-vault-0 -- vault operator unseal <UNSEAL_KEY>

## Join the other two nodes

ubuntu@k3s-au:~/vault$ k exec -it consul-vault-1 -- vault operator raft join http://<ACTIVE_NODE_IP>:8200

ubuntu@k3s-au:~/vault$ k exec -it consul-vault-2 -- vault operator raft join http://<ACTIVE_NODE_IP>:8200


## Unseal both pods

k exec -it consul-vault-1 -- vault operator unseal <unseal_key>
k exec -it consul-vault-2 -- vault operator unseal <unseal_key>
