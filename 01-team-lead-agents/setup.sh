#!/bin/sh

export CLUSTER_NAME="kagent-oss-demo"

echo; echo "************ Creating ${CLUSTER_NAME} ************"
kind create cluster --name ${CLUSTER_NAME} --config kind-config.yaml

# wait for cluster to be ready before installing GME agents
kubectl --context kind-${CLUSTER_NAME} -n kube-system rollout status deploy/coredns
kubectl --context kind-${CLUSTER_NAME} -n local-path-storage rollout status deploy/local-path-provisioner
kubectl --context kind-${CLUSTER_NAME} -n kube-system rollout status ds/kindnet
kubectl --context kind-${CLUSTER_NAME} -n kube-system rollout status ds/kube-proxy
