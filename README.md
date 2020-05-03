# How to setup the cluster

This repository contains necessary manifests and scripts for setting up a Kubernetes cluster
on Ampere. While the goal is to facilitate automated setup of a hybrid cluster, it currently
just works on aarch64/ARM64. For usage information, see the [getting started guide](getting-started.md).

## Reference stack components

| component | solution | 
|-----------|-----------------|
|  CNI | canal    |
|  metrics | core-metrics    |
|  dashboard    |   kube-dashboard   |
|  logging | Elastic/fluentd (WIP - not supported today) |
|  monitoring | prometheus |
|  storage /CSI | rook - ceph   |
|  sandboxed-runtime | kata (WIP), gvisor (WIP) |
|  ingres | nginx |
|  load-balancer | metallb |

## ARM support status

| component | container image | build  | container  | mult-arch |
|-----------|-----------------|--------|------------|-----------|
|  CNI-canal    |   <all>         | yes | yes   |  NO  |
|  core-metrics    |   <all>         | yes | yes   |  NO  |
|  dashboard    |   <all>         |  |    |    |
|  Elastic/fluentd   |   <all>         |  |    |    |
|  prometheus    |   grafana  | yes  | yes  | yes |
|  prometheus    |   (rest)  | yes | no  | no |
|  rook     |   <all>         | yes | yes   |  yes  |
|  kata  |   kata-deploy | yes | no  | no |
|  ingres (nginx) | <all> | yes | yes  | yes |
|  metallb | <all> | yes | yes  | yes |

## Credits

Much of the framework is based on the excellent Clear Linux kubernetes [examples project](https://github.com/clearlinux/cloud-native-setup/tree/master/clr-k8s-examples). Modifications were primarily created to simplify the setup, use Ubuntu as the reference for
nodes, and update manifests to work on aarch64/ARM64. For these updates, where multi-arch or ARM64 images are not available,
[@carlosedp](https://github.com/carlosedp)'s great work to provide equivalent images is leveraged.

