#!/bin/sh
# variables
PKS_DIRECTOR=IPBOSHDIRECTORPKS
PKS_OPSMGR_FQDN=opsmgr-pks-calico.sandbox.foundry.sii24.pole-emploi.intra
DOTK="-k"
ADMIN="admin"
PASSWORD="PASSWORDOPSMANAGER"
PKS_CACRT="ca.pks.crt"

# get certificat pks opsmgr
OM_PKS="om $DOTK -t https://${PKS_OPSMGR_FQDN} -u ${ADMIN} -p ${PASSWORD}"
$OM_PKS curl -p /api/v0/certificate_authorities -s | jq -r '.certificate_authorities | select(map(.active == true))[0] | .cert_pem' > $PKS_CACRT

# get BOSH PKS password
BOSH_PKS_PASSWD=$($OM_PKS curl -p /api/v0/deployed/director/credentials/director_credentials -s | jq '.[] | .value.password' | sed -e "s/\"//g" )

# Access bosh
bosh alias-env pks -e ${PKS_DIRECTOR} --ca-cert $PKS_CACRT
echo -e "director\n${BOSH_PKS_PASSWD}" | bosh -e pks log-in
