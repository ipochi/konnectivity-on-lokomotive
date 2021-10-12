#!/bin/bash

set -euo pipefail

PROXY_IMAGE=${PROXY_IMAGE:-"us.gcr.io/k8s-artifacts-prod/kas-network-proxy/proxy-server:v0.0.24"}
AGENT_IMAGE=${AGENT_IMAGE:-"us.gcr.io/k8s-artifacts-prod/kas-network-proxy/proxy-agent:v0.0.24"}
CLUSTER_CERT=${CLUSTER_CERT:-"/etc/kubernetes/secrets/apiserver.crt"}
CLUSTER_KEY=${CLUSTER_KEY:-"/etc/kubernetes/secrets/apiserver.key"}
FIRST_RUN=${FIRST_RUN:-"no"}
ASSETS_DIR=${ASSETS_DIR:-"$(pwd)"}

CLUSTER_IP=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | cut -d/ -f3 | cut -d: -f1)

function create_rbac() {
  kubectl apply -f rbac.yaml
}

function create_globalnetworkpolicy() {
  kubectl apply -f global-network-policy.yaml
}

function create_egress_selector_secret() {
  kubectl create secret -n kube-system generic egress-selector-config --from-file=egress-selector-config=egress-selector-config.yaml
}

function generate_certs_and_kubeconfig() {
  cert_dir="gen_certs"
  mkdir -p ${cert_dir}

  dir="${ASSETS_DIR}/cluster-assets/tls"
  ca_crt="${dir}/ca.crt"
  ca_key="${dir}/ca.key"

  openssl req -subj "/CN=system:konnectivity-server" -new -newkey rsa:2048 -nodes -out ${cert_dir}/konnectivity.csr -keyout ${cert_dir}/konnectivity.key -out ${cert_dir}/konnectivity.csr
  openssl x509 -req -in ${cert_dir}/konnectivity.csr -CA ${ca_crt} -CAkey ${ca_key} -CAcreateserial -out ${cert_dir}/konnectivity.crt -days 375 -sha256
  SERVER=$(kubectl config view -o jsonpath='{.clusters..server}')

  kubectl --kubeconfig kubeconfig config set-credentials system:konnectivity-server --client-certificate ${cert_dir}/konnectivity.crt --client-key ${cert_dir}/konnectivity.key --embed-certs=true
  kubectl --kubeconfig kubeconfig config set-cluster kubernetes --server "$SERVER" --certificate-authority ${ca_crt} --embed-certs=true
  kubectl --kubeconfig kubeconfig config set-context system:konnectivity-server@kubernetes --cluster kubernetes --user system:konnectivity-server
  kubectl --kubeconfig kubeconfig config use-context system:konnectivity-server@kubernetes
}

function create_konnectivity_kubeconfig_secret() {
  kubectl -n kube-system create secret generic konnectivity-kubeconfig --from-file=kubeconfig=kubeconfig
}

function install_konnectivity_proxy_server() {
  PROXY_IMAGE=${PROXY_IMAGE} envsubst < konnectivity-server.yaml | kubectl apply -f -
}

function install_konnectivity_proxy_agent() {
  AGENT_IMAGE=${AGENT_IMAGE} CLUSTER_IP=${CLUSTER_IP} envsubst < konnectivity-agent.yaml | kubectl apply -f -
}

function patch_apiserver_deployment() {
  kubectl patch deployment kube-apiserver -n kube-system --type="json" \
  -p='[
  {"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "konnectivity-uds", "hostPath": {"path": "/var/konnectivity-server", "type": "DirectoryOrCreate"}}},
  {"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "konnectivity-config", "secret": {"secretName": "egress-selector-config", "defaultMode": 420}}},
  {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "konnectivity-uds", "mountPath":"/var/konnectivity-server","readOnly":false}},
  {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "konnectivity-config", "mountPath":"/var/konnectivity-server/config","readOnly":true}},
  {"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--api-audiences=https://kubernetes.default.svc,system:konnectivity-server"},
  {"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--egress-selector-config-file=/var/konnectivity-server/config/egress-selector-config"}]'
}

generate_certs_and_kubeconfig
create_konnectivity_kubeconfig_secret
create_rbac
create_globalnetworkpolicy
create_egress_selector_secret
install_konnectivity_proxy_server
install_konnectivity_proxy_agent
patch_apiserver_deployment
