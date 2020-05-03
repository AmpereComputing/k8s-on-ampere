## Prerequisite
This setup currently will work with Kubernetes 1.14 & above. Any version of Kubernetes before that might work, but is not guaranteed.

Run [`setup_system.sh`](setup_system.sh) once on each and every node (master and workers)
to ensure Kubernetes works on it.

### Configuration for high numbers of pods per node

In order to enable running greater than 110 pods per node, set the environment
variable `HIGH_POD_COUNT` to any non-empty value.

> NOTE: Use this configuration when utilizing the [metrics](../metrics) tooling in this repo.

## Bring up the master

Run [`create_stack.sh`](create_stack.sh) on the master node. This sets up the
master and also uses kubelet config via [`kubeadm.yaml`](kubeadm.yaml)
to propagate cluster wide kubelet configuration to all workers. Customize it if
you need to setup other cluster wide properties.

There are different flavors to install, run `./create_stack.sh help` to get
more information.

> NOTE: Before running [`create_stack.sh`](create_stack.sh) script, make sure to export
the necessary environment variables if needed to be changed. By default it will use
`CLRK8S_CNI` to be canal, and `CLRK8S_RUNNER` to be crio. Cilium is tested only in the 
Vagrant.

```bash
# default shows help
./create_stack.sh <subcommand>
```

In order to enable running greater than 110 pods per node, set the environment
variable `HIGH_POD_COUNT` to any non-empty value.

## Accessing control plane services

### Pre-req

You need to have credentials of the cluster, on the computer
you will be accessing the control plane services from. If it is not under
`$HOME/.kube`, set `KUBECONFIG` environment variable for `kubectl` to find.

### Dashboard

```bash
kubectl proxy # starts serving on 127.0.0.1:8001
```

Dashboard is available at this URL
http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy

### Kibana

Start proxy same as above. Kibana is available at this URL
http://localhost:8001/api/v1/namespaces/kube-system/services/kibana-logging/proxy/app/kibana

### Grafana

```bash
kubectl -n monitoring port-forward svc/grafana 3000
```

Grafana is available at this URL http://localhost:3000 . Default credentials are
`admin/admin`. Upon entering you will be asked to chose a new password.

## Cleaning up the cluster (Hard reset to a clean state)

Run `reset_stack.sh` on all the nodes

## Additional Components

### Rook
The default Rook configuration provided is intended for testing purposes only
and is not suitable for a production environment. By default Rook is configured
to provide local storage (/var/lib/rook) and will be provisioned differently
depending on whether or not you startup a single node Kubernetes cluster, or
a multiple node Kubernetes cluster. 

- When starting up a single node Kubernetes cluster, Rook will be configured
to start up a single replica, and will allow multiple monitors on the same node.
- When multiple Kubernetes worker nodes are detected, Rook will be configured
to startup a replica on each available node and will schedule monitor processes
on separate nodes providing greater reliability.
