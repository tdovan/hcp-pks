#!/bin/bash
#
# Copyright (c) 2019, Hewlett Packard Enterprise Development LP
#
#set -x
#set -e

#source $BUNDLE_COMMON_DIR/common.sh
export K8S_BOOTSTRAP_DIR="/root/workspace-jear/pks/hpecp"
export KD_TEMPLATES_DIR="$K8S_BOOTSTRAP_DIR/operator-templates"

# This tag could be used by HPECP agent in the future. Is not now.
export TENANT_NET_ISOLATION_TAG="tenantNetworkIsolation=true"

export OPERATOR_NAMESPACE="hpecp"


# install_configure_operators() {
kubectl create namespace $OPERATOR_NAMESPACE
kubectl label namespace $OPERATOR_NAMESPACE $TENANT_NET_ISOLATION_TAG

# install_start_operators() {
    # Wait a bit for network to settle. This is not a functional requirement
    # but helps get rid of various initial errors in logs.
    # XXX Could remove this if we add a reliable test for network-finally-up.
    sleep 60

    # Set repos for operator images.

export HPECPAGENT_REPO="docker.io/bluedata"
export KUBEDIRECTOR_REPO="docker.io/bluek8s"

if [ ! -z "$bds_k8s_containerrepo" ]
then
    HPECPAGENT_REPO=$bds_k8s_containerrepo
    KUBEDIRECTOR_REPO=$bds_k8s_containerrepo
fi

    # RBACs and CRDs

kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/hpecp-rbac.yaml
kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/kd-rbac.yaml
kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/crds

    # Deploy HPECP Agent

    util_copy_file $KD_TEMPLATES_DIR/hpecp-deployment-prebuilt-template.yaml $KD_TEMPLATES_DIR/hpecp-deployment-prebuilt.yaml
    log_exec "sed -i 's|@@@@HPECP_AGENT@@@@|$HPECPAGENT_REPO|g' $KD_TEMPLATES_DIR/hpecp-deployment-prebuilt.yaml"
kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/hpecp-deployment-prebuilt.yaml

    # Create config CR after modifying the unrestricted-mounts namespace.
    log_exec "sed -i 's|@@@@OPERATOR_NAMESPACE@@@@|$OPERATOR_NAMESPACE|g' $KD_TEMPLATES_DIR/config-crs/cr-hpecp-config.yaml"
kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/config-crs/cr-hpecp-config.yaml
    # Patch a shorter timeout into the "soft" webhook defined by HPECP Agent;
    # it is intended that this webhook being down should not block client
    # requests. Therefore a shorter timeout is needed so that webhook timeout
    # can happen before any API client timeout.
    # Ideally the agent would set this when creating the webhook, but we need to
    # move to a more recent version of the operator SDK (v0.11 or better) to
    # get access to that property in the APIs.
    WebhookPatch="'{\"webhooks\":[{\"name\":\"soft-validate.hpecp.hpe.com\",\"timeoutSeconds\":10}]}'"
kubectl patch MutatingWebhookConfiguration hpecp-webhook -p $WebhookPatch

    # Deploy KubeDirector

    util_copy_file $KD_TEMPLATES_DIR/kd-deployment-prebuilt-template.yaml $KD_TEMPLATES_DIR/kd-deployment-prebuilt.yaml
    log_exec "sed -i 's|@@@@BLUEK8S_KUBEDIRECTOR@@@@|$KUBEDIRECTOR_REPO|g' $KD_TEMPLATES_DIR/kd-deployment-prebuilt.yaml"
kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/kd-deployment-prebuilt.yaml
    

# Create config CR after modifying the cluster domain.
    log_exec "sed -i 's|@@@@CLUSTER_DOMAIN@@@@|$bds_k8s_dnsdomain|g' $KD_TEMPLATES_DIR/config-crs/cr-kd-config.yaml"
kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/config-crs/cr-kd-config.yaml

    # Set repos for kdapp images.

    DOCKER_REPO="docker.io/bluedata"
    if [ ! -z "$bds_k8s_containerrepo" ]
    then
        DOCKER_REPO=$bds_k8s_containerrepo
    fi

    # Create webterm app cr after modifying the docker image repository location in operator namespace
    log_exec "sed -i 's|@@@@WEBTERM_IMAGE@@@@|$DOCKER_REPO|g' $KD_TEMPLATES_DIR/cr-app-webterm.json"
kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/cr-app-webterm.json

    # All kubedirector apps must go in kd-apps namespace
kubectl create ns kd-apps
kubectl -n kd-apps create -f $KD_TEMPLATES_DIR/app-crs



