#!/usr/bin/env bash

###
#  create_stack.sh - Intialize a Kubernetes cluster and install components
##

set -o errexit
set -o pipefail
set -o nounset

CUR_DIR=$(pwd)
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
: ${TOKEN:=}
: ${MASTER_IP:=}
: ${CERT_SANS:=}
HIGH_POD_COUNT=${HIGH_POD_COUNT:-""}

# versions
CANAL_VER="${CANAL_VER:-v3.10}"
K8S_VER="${K8S_VER:-}"
ROOK_VER="${ROOK_VER:-v1.2.6}"
METRICS_VER="${METRICS_VER:-v0.3.6}"
DASHBOARD_VER="${DASHBOARD_VER:-v2.0.0-beta2}"
INGRES_VER="${INGRES_VER:-controller-0.32.0}"
METALLB_VER="${METALLB_VER:-v0.8.3}"
PROMETHEUS_VER="${PROMETHEUS_VER:-v0.5.0}"
CNI=${CNI:-"canal"}

# Default to multi-node, but this will be overwritten to standalone
# *if* a single node cluster
mode="multinode"

function print_usage_exit() {
    exit_code=${1:-0}
    cat <<EOT
Usage: $0 [subcommand]

Subcommands:

$(
        for cmd in "${!command_handlers[@]}"; do
            printf "\t%s:|\t%s\n" "${cmd}" "${command_help[${cmd}]:-Not-documented}"
        done | sort | column -t -s "|"
    )
EOT
exit "${exit_code}"
}

function finish() {
    cd "${CUR_DIR}"
}

trap finish EXIT

function cluster_init() {
   
    sudo systemctl restart containerd

    sudo -E kubeadm init --config=./kubeadm.yaml

    rm -rf "${HOME}/.kube"
    mkdir -p "${HOME}/.kube"
    sudo cp -i /etc/kubernetes/admin.conf "${HOME}/.kube/config"
    sudo chown "$(id -u):$(id -g)" "${HOME}/.kube/config"

    # Ensure single node k8s works
    if [ "$(kubectl get nodes | wc -l)" -eq 2 ]; then
        kubectl taint nodes --all node-role.kubernetes.io/master-
        mode="standalone"
    fi
}

function cni() {
    case "$CNI" in
        canal)
            # note version is not semver
            CANAL_VER=${1:-$CANAL_VER}
            CANAL_URL="https://docs.projectcalico.org/${CANAL_VER}/manifests"
            if [[ "$CANAL_VER" == "v3.3" ]]; then
                CANAL_URL="https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/canal"
            fi
            CANAL_DIR="0-canal"

            # canal manifests are not kept in repo but in docs site so use curl
            mkdir -p "${CANAL_DIR}/overlays/${CANAL_VER}/canal"
            curl -o "${CANAL_DIR}/overlays/${CANAL_VER}/canal/canal.yaml" "$CANAL_URL/canal.yaml"
           
            # canal doesnt pass kustomize validation
            kubectl apply -k "${CANAL_DIR}/overlays/${CANAL_VER}"
            ;;
        cilium)

            echo "cilium currently not supported"
            exit 1

            ;;
        *)
            echo"Unknown cni $CNI"
            exit 1
            ;;
    esac
}

function metrics() {
    METRICS_VER="${1:-$METRICS_VER}"
    METRICS_URL="https://github.com/kubernetes-incubator/metrics-server.git"
    METRICS_DIR="1-core-metrics"

    get_repo "${METRICS_URL}" "${METRICS_DIR}/overlays/${METRICS_VER}"
    set_repo_version "${METRICS_VER}" "${METRICS_DIR}/overlays/${METRICS_VER}/metrics-server"

    kubectl apply -k "${METRICS_DIR}/overlays/${METRICS_VER}"
}

function wait_on_pvc() {
    # create and destroy pvc until successful
    while [[ $(kubectl get pvc test-pv-claim --no-headers | grep Bound -c) -ne 1 ]]; do
        sleep 30
        kubectl delete pvc test-pv-claim
        create_pvc
        sleep 10
    done
}

function create_pvc() {
    kubectl apply -f - <<HERE
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pv-claim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Mi
HERE
}

function storage() {
    # start rook before any other component that requires storage
    ROOK_VER="${1:-$ROOK_VER}"
    ROOK_URL="https://github.com/rook/rook.git"
    ROOK_DIR=7-rook

    # get and apply rook
    get_repo "${ROOK_URL}" "${ROOK_DIR}/overlays/${ROOK_VER}/${mode}"
    set_repo_version "${ROOK_VER}" "${ROOK_DIR}/overlays/${ROOK_VER}/${mode}/rook"
    kubectl apply -k "${ROOK_DIR}/overlays/${ROOK_VER}/${mode}"
    # wait for the rook OSDs to run which means rooks should be ready
    while [[ $(kubectl get po --all-namespaces | grep -e 'osd.*Running.*' -c) -lt 1 ]]; do
        echo "Waiting for Rook OSD"
        sleep 60
    done

    # set default storageclass
    kubectl patch storageclass rook-ceph-block -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

    create_pvc
    # wait for pvc so subsequent pods have storage
    wait_on_pvc
}

function monitoring() {

    #
    # Grafana works...
    # Need to add ARM support for state-metrics, node-exporter, the prom adapter and operator
    # 

    PROMETHEUS_VER=${1:-$PROMETHEUS_VER}
    PROMETHEUS_URL="https://github.com/coreos/kube-prometheus.git"
    PROMETHEUS_DIR="4-kube-prometheus"
    get_repo "${PROMETHEUS_URL}" "${PROMETHEUS_DIR}/overlays/${PROMETHEUS_VER}"
    set_repo_version "${PROMETHEUS_VER}" "${PROMETHEUS_DIR}/overlays/${PROMETHEUS_VER}/kube-prometheus"

    # HACK: not sure how to 'fixup' the config-reloader container argument within setup/prometheus-operator-deployment.yaml
    #  using kustomize, without just introducing patch file. I don't want to do this just yet, so let's just sed the yaml:
    sed -i 's/prometheus-config-reloader:v0.38.1/prometheus-config-reloader:master/' \
        "${PROMETHEUS_DIR}/overlays/${PROMETHEUS_VER}/kube-prometheus/manifests/setup/prometheus-operator-deployment.yaml"

    kubectl apply -f "${PROMETHEUS_DIR}/overlays/${PROMETHEUS_VER}/kube-prometheus/manifests/setup/"
    kubectl apply -k "${PROMETHEUS_DIR}/overlays/${PROMETHEUS_VER}"
    

    while [[ $(kubectl get crd alertmanagers.monitoring.coreos.com prometheuses.monitoring.coreos.com prometheusrules.monitoring.coreos.com servicemonitors.monitoring.coreos.com >/dev/null 2>&1) || $? -ne 0 ]]; do
        echo "Waiting for Prometheus CRDs"
        sleep 2
    done

    #Expose the dashboards
    #kubectl --namespace monitoring port-forward svc/prometheus-k8s 9090 &
    #kubectl --namespace monitoring port-forward svc/grafana 3000 &
    #kubectl --namespace monitoring port-forward svc/alertmanager-main 9093 &
}

function dashboard() {
    DASHBOARD_VER=${1:-$DASHBOARD_VER}
    DASHBOARD_URL="https://github.com/kubernetes/dashboard.git"
    DASHBOARD_DIR="2-dashboard"
    get_repo "${DASHBOARD_URL}" "${DASHBOARD_DIR}/overlays/${DASHBOARD_VER}"
    set_repo_version "${DASHBOARD_VER}" "${DASHBOARD_DIR}/overlays/${DASHBOARD_VER}/dashboard"
    kubectl apply -k "${DASHBOARD_DIR}/overlays/${DASHBOARD_VER}"
}

function ingres() {
    INGRES_VER=${1:-$INGRES_VER}
    INGRES_URL="https://github.com/kubernetes/ingress-nginx.git"
    INGRES_DIR="5-ingres-lb"
    get_repo "${INGRES_URL}" "${INGRES_DIR}/overlays/${INGRES_VER}"
    set_repo_version "${INGRES_VER}" "${INGRES_DIR}/overlays/${INGRES_VER}/ingress-nginx"
    kubectl apply -k "${INGRES_DIR}/overlays/${INGRES_VER}"
}

function efk() {

    ECK_VERSION="1.1.2"
    ECK_YAML="https://download.elastic.co/downloads/eck/${ECK_VERSION}/all-in-one.yaml"
    ECK_DIR="3-eck_fb"

    wget "$ECK_YAML"
    mv all-in-one.yaml "${ECK_DIR}/overlays/${ECK_VERSION}"
    kubectl apply -k "${ECK_DIR}/overlays/${ECK_VERSION}"


    kubectl apply -f "${ECK_DIR}/ek"

    while [[ $(kubectl get kibana -o=jsonpath='{.items[0].status.health}') != "green" ]]; do echo "waiting for kibana" && sleep 5; done

    kubectl apply -f "${ECK_DIR}/fluent-bit/fluent-bit-role-sa.yaml"
    kubectl apply -f "${ECK_DIR}/fluent-bit/fluent-bit-configmap.yaml"
    kubectl apply -f "${ECK_DIR}/fluent-bit/fluent-bit-ds.yaml"

    expected=$(kubectl get ds fluent-bit -o json | jq '.status.desiredNumberScheduled')
    while [[ $(kubectl get ds fluent-bit -o=jsonpath="{.status.numberReady}") != "$expected" ]]; do echo "waiting for ds" && sleep 5; done


    echo "EFK is up"
}

function metallb() {
    METALLB_VER=${1:-$METALLB_VER}
    METALLB_URL="https://github.com/danderson/metallb.git"
    METALLB_DIR="6-metal-lb"
    get_repo "${METALLB_URL}" "${METALLB_DIR}/overlays/${METALLB_VER}"
    set_repo_version "${METALLB_VER}" "${METALLB_DIR}/overlays/${METALLB_VER}/metallb"
    kubectl apply -k "${METALLB_DIR}/overlays/${METALLB_VER}"
}

function miscellaneous() {
    # dashboard
    dashboard

    #Create an ingress load balancer
    ingres

    #Create a bare metal load balancer.
    #kubectl apply -f 6-metal-lb/metallb.yaml

    #The config map should be properly modified to pick a range that can live
    #on this subnet behind the same gateway (i.e. same L2 domain)
    #kubectl apply -f 6-metal-lb/example-layer2-config.yaml
}

function minimal() {
    cluster_init
    cni
}

function all() {
    minimal
    metrics
    monitoring
    miscellaneous
    # Storage succeeds in started, but has an error signal which will exit this script.
    # TODO: Fix, but for now just to this last. Hacky, i know...
    efk
}

function get_repo() {
    local repo="${1}"
    local path="${2}"
    clone_dir=$(basename "${repo}" .git)
    [[ -d "${path}/${clone_dir}" ]] || git -C "${path}" clone "${repo}"

}

function set_repo_version() {
    local ver="${1}"
    local path="${2}"
    pushd "$(pwd)"
    cd "${path}"
    git fetch origin "${ver}"
    git -c advice.detachedHead=false checkout "${ver}"
    popd

}

###
# main
##

declare -A command_handlers
command_handlers[init]=cluster_init
command_handlers[cni]=cni
command_handlers[minimal]=minimal
command_handlers[dashboard]=dashboard
command_handlers[efk]=efk
command_handlers[metrics]=metrics
command_handlers[all]=all
command_handlers[help]=print_usage_exit
command_handlers[storage]=storage
command_handlers[monitoring]=monitoring
command_handlers[ingres]=ingres
command_handlers[metallb]=metallb

declare -A command_help
command_help[init]="Only inits a cluster using kubeadm"
command_help[cni]="Setup network for running cluster"
command_help[minimal]="init + cni"
command_help[all]="minimal + storage + monitoring + miscellaneous"
command_help[help]="show this message"
command_help[nfd]="node feature discovery"

cd "${SCRIPT_DIR}"

cmd_handler=${command_handlers[${1:-none}]:-unimplemented}
if [ "${cmd_handler}" != "unimplemented" ]; then
    if [ $# -eq 1 ]; then
        "${cmd_handler}"
        exit $?
    fi

    "${cmd_handler}" "$2"

else
    print_usage_exit 1
fi
