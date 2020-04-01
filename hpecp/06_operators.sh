#!/bin/bash
#
# Copyright (c) 2019, Hewlett Packard Enterprise Development LP
#
#set -x
#set -e

source $BUNDLE_COMMON_DIR/common.sh
K8S_BOOTSTRAP_DIR=$(dirname $(readlink -nf ${BASH_SOURCE[0]}))
KD_TEMPLATES_DIR="$K8S_BOOTSTRAP_DIR/operator-templates"

# This tag could be used by HPECP agent in the future. Is not now.
TENANT_NET_ISOLATION_TAG="tenantNetworkIsolation=true"

OPERATOR_NAMESPACE="hpecp"


#
# INTERNAL FUNCTIONS
#

#
# API FUNCTIONS BASED ON MODE AND STEP
#
install_stop_operators() {
    return 0
}

install_configure_operators() {
    log_exec kubectl create namespace $OPERATOR_NAMESPACE
    log_exec kubectl label namespace $OPERATOR_NAMESPACE $TENANT_NET_ISOLATION_TAG
    return 0
}

install_start_operators() {

    # Wait a bit for network to settle. This is not a functional requirement
    # but helps get rid of various initial errors in logs.
    # XXX Could remove this if we add a reliable test for network-finally-up.
    sleep 60

    # Set repos for operator images.

    HPECPAGENT_REPO="docker.io/bluedata"
    KUBEDIRECTOR_REPO="docker.io/bluek8s"
    if [ ! -z "$bds_k8s_containerrepo" ]
    then
        HPECPAGENT_REPO=$bds_k8s_containerrepo
        KUBEDIRECTOR_REPO=$bds_k8s_containerrepo
    fi

    # RBACs and CRDs

    log_exec kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/hpecp-rbac.yaml
    log_exec kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/kd-rbac.yaml
    log_exec kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/crds

    # Deploy HPECP Agent

    util_copy_file $KD_TEMPLATES_DIR/hpecp-deployment-prebuilt-template.yaml $KD_TEMPLATES_DIR/hpecp-deployment-prebuilt.yaml
    log_exec "sed -i 's|@@@@HPECP_AGENT@@@@|$HPECPAGENT_REPO|g' $KD_TEMPLATES_DIR/hpecp-deployment-prebuilt.yaml"
    log_exec kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/hpecp-deployment-prebuilt.yaml
    Retries=30
    while [ "$Retries" -gt 0 ]; do
        log_exec_no_exit "kubectl -n $OPERATOR_NAMESPACE get pods -l name=hpecp-agent"
        if [[ $? -eq 0 ]]; then
            break
        fi
        log "Waiting for HPECP Agent to start..."
        Retries=`expr $Retries - 1`
        sleep 10
    done
    if [[ "$Retries" -eq 0 ]]; then
        log "Failed waiting for HPECP Agent to start."
        exit 1
    fi
    # Wait upto 15 minutes for the agent to respond
    Retries=30
    while [ "$Retries" -gt 0 ]; do
        SvcAddr=$(log_exec_no_exit "kubectl -n $OPERATOR_NAMESPACE get svc hpecp-validator -o jsonpath=\"{.spec.clusterIP}\"")
        if [ "$SvcAddr" != '' ]; then
            Health=$(log_exec_no_exit "curl --connect-timeout 2 --noproxy '*' -k https://$SvcAddr:443/healthz")
            if [ "$Health" == 'ok' ]; then
                break
            fi
        fi
        log "Waiting for HPECP Agent admission control hook to be responsive..."
        Retries=`expr $Retries - 1`
        sleep 30
    done
    if [[ "$Retries" -eq 0 ]]; then
        log "Failed waiting for HPECP Agent admission control hook to respond."
        exit 1
    fi
    # Create config CR after modifying the unrestricted-mounts namespace.
    log_exec "sed -i 's|@@@@OPERATOR_NAMESPACE@@@@|$OPERATOR_NAMESPACE|g' $KD_TEMPLATES_DIR/config-crs/cr-hpecp-config.yaml"
    log_exec kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/config-crs/cr-hpecp-config.yaml
    # Patch a shorter timeout into the "soft" webhook defined by HPECP Agent;
    # it is intended that this webhook being down should not block client
    # requests. Therefore a shorter timeout is needed so that webhook timeout
    # can happen before any API client timeout.
    # Ideally the agent would set this when creating the webhook, but we need to
    # move to a more recent version of the operator SDK (v0.11 or better) to
    # get access to that property in the APIs.
    WebhookPatch="'{\"webhooks\":[{\"name\":\"soft-validate.hpecp.hpe.com\",\"timeoutSeconds\":10}]}'"
    log_exec_no_exit "kubectl patch MutatingWebhookConfiguration hpecp-webhook -p $WebhookPatch"

    # Deploy KubeDirector

    util_copy_file $KD_TEMPLATES_DIR/kd-deployment-prebuilt-template.yaml $KD_TEMPLATES_DIR/kd-deployment-prebuilt.yaml
    log_exec "sed -i 's|@@@@BLUEK8S_KUBEDIRECTOR@@@@|$KUBEDIRECTOR_REPO|g' $KD_TEMPLATES_DIR/kd-deployment-prebuilt.yaml"
    log_exec kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/kd-deployment-prebuilt.yaml
    Retries=30
    while [ "$Retries" -gt 0 ]; do
        log_exec_no_exit "kubectl -n $OPERATOR_NAMESPACE get pods -l name=kubedirector"
        if [[ $? -eq 0 ]]; then
            break
        fi
        log "Waiting for KubeDirector to start..."
        Retries=`expr $Retries - 1`
        sleep 10
    done
    if [[ "$Retries" -eq 0 ]]; then
        log "Failed waiting for KubeDirector to start."
        exit 1
    fi
    Retries=30
    while [ "$Retries" -gt 0 ]; do
        SvcAddr=$(log_exec_no_exit "kubectl -n $OPERATOR_NAMESPACE get svc kubedirector-validator -o jsonpath=\"{.spec.clusterIP}\"")
        if [ "$SvcAddr" != '' ]; then
            Health=$(log_exec_no_exit "curl --connect-timeout 2 --noproxy '*' -k https://$SvcAddr:443/healthz")
            if [ "$Health" == 'ok' ]; then
                break
            fi
        fi
        log "Waiting for KubeDirector admission control hook to be responsive..."
        Retries=`expr $Retries - 1`
        sleep 10
    done
    if [[ "$Retries" -eq 0 ]]; then
        log "Failed waiting for KubeDirector admission control hook to respond."
        exit 1
    fi
    # Create config CR after modifying the cluster domain.
    log_exec "sed -i 's|@@@@CLUSTER_DOMAIN@@@@|$bds_k8s_dnsdomain|g' $KD_TEMPLATES_DIR/config-crs/cr-kd-config.yaml"
    log_exec kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/config-crs/cr-kd-config.yaml

    # Set repos for kdapp images.

    DOCKER_REPO="docker.io/bluedata"
    if [ ! -z "$bds_k8s_containerrepo" ]
    then
        DOCKER_REPO=$bds_k8s_containerrepo
    fi

    # Create webterm app cr after modifying the docker image repository location in operator namespace
    log_exec "sed -i 's|@@@@WEBTERM_IMAGE@@@@|$DOCKER_REPO|g' $KD_TEMPLATES_DIR/cr-app-webterm.json"
    log_exec kubectl -n $OPERATOR_NAMESPACE create -f $KD_TEMPLATES_DIR/cr-app-webterm.json

    # All kubedirector apps must go in kd-apps namespace
    log_exec kubectl create ns kd-apps
    log_exec kubectl -n kd-apps create -f $KD_TEMPLATES_DIR/app-crs

    return 0
}

install_rollback_operators() {
    [[ "${ROLLBACK_ON_ERROR}" == 'false' ]] && return 0

    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete KubeDirectorCluster --all --now
    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete KubeDirectorApp --all --now
    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete KubeDirectorConfig --all --now
    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete HPECPFsMount --all --now
    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete HPECPTenant --all --now
    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete HPECPConfig --all --now

    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete -f $KD_TEMPLATES_DIR/kd-deployment-prebuilt.yaml --now
    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete -f $KD_TEMPLATES_DIR/hpecp-deployment-prebuilt.yaml --now

    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete -f $KD_TEMPLATES_DIR/crds

    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete -f $KD_TEMPLATES_DIR/kd-rbac.yaml
    log_exec_no_exit kubectl -n $OPERATOR_NAMESPACE delete -f $KD_TEMPLATES_DIR/hpecp-rbac.yaml

    log_exec_no_exit kubectl delete namespace $OPERATOR_NAMESPACE

    # XXX FIXME. Need to clean out more?

    # XXX FIXME. Wait for all resources to be cleaned out
    return 0
}

install_finalize_operators() {
    return 0
}

upgrade_stop_operators() {
    return 0
}

upgrade_prepare_operators() {
    return 0
}

upgrade_configure_operators() {
    return 0
}

upgrade_start_operators() {
    return 0
}

upgrade_finalize_operators() {
    return 0
}

upgrade_rollback_operators() {
    return 0
}

if [ "$PLHA" == 'false' ]; then
    ${MODE}_${STEP}_operators
else
    # Modify code here if the components should handle PLHA related
    # (re)configuration.
    exit 0
fi
