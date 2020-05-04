# Kubernetes on Ampere

This repository contains necessary manifests and scripts for setting up a Kubernetes cluster
on Ampere. While the goal is to facilitate automated setup of a hybrid cluster, it currently
just works on aarch64/ARM64. For usage information, see the [getting started guide](getting-started.md).

For details on next steps, plans, see the following [GitHub project dashboard](https://github.com/egernst/k8s-on-ampere/projects)

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

Support for aarch64 varies across projects, including the ones utilized in this
reference stack. The level of support for each component is described below. In
the worst case, a project does not have support for building aarch64. For those that
do, not all provide artifacts. If artifacts are provided, they aren't necessarily available
in a standard (that is, hosted by the project) container image. In the best case, aarch64
is built and deployed using multi-architecture container images. In that case, the same manifest
can be shared between architectures, allowing ease of deployment in a 'mixed cluster.'

The table below provides a summary of status for the components in this reference stack

| component | container image (name) | build support  | container/artifacts provided  | multi-arch container support |
|-----------|-----------------|--------|------------|-----------|
|  CNI-canal    |   all       | yes    | yes        |  no       |
|  core-metrics |   all       | yes    | yes        |  no       |
|  dashboard    |             |        |            |           |
|  EFK      |  fluentd        | yes    |       yes  |     no    |
|  EFK      | elasticsearch   |  yes   |   no       |  no       |
|  EFK      |     kibana      |  no    |   no       |  no       |
|  prometheus |      grafana  |   yes  | yes        | yes       |
|  prometheus |   (rest)      |    yes |        no  | no        |
|  rook     |     all         | yes    | yes        |  yes      |
|  kata  |   kata-deploy      | yes    | no         | no        |
|  gvisor  |  n/a             | yes    | no release bins |  no  |
|  ingres (nginx) | (all)     | yes    | yes         | yes      |
|  metallb | (all)            | yes    | yes         | yes      |

## Future work

- Once multi-arch support is enabled for the entire reference stack, the even better best case is making sure that the projects run optimally on aarch64. It will be interesting to profile some of the key infrastructure components and see where utilizing latest ISA features (ie, built with latest compilers/tools) could result in improved performance.
- Expand to include other typical production components, like:
  - security filtering,
  - service mesh,
  - more CNI options,
  - expanded node exporters

## Credits

Much of the framework is based on the excellent Clear Linux kubernetes [examples project](https://github.com/clearlinux/cloud-native-setup/tree/master/clr-k8s-examples). Modifications were primarily created to simplify the setup, use Ubuntu as the reference for
nodes, and update manifests to work on aarch64/ARM64. For these updates, where multi-arch or ARM64 images are not available,
[@carlosedp](https://github.com/carlosedp)'s great work to provide equivalent images is leveraged.

