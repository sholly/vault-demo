#!/usr/bin/env bash
set -x 

echo VAULT_ADDR = $VAULT_ADDR
echo VAULT_USERROLE = $VAULT_USERROLE
echo APP_NAME = $APP_NAME

JWT=`cat /var/run/secrets/kubernetes.io/serviceaccount/token`

echo JWT = $JWT

cat <<EOF > payload.json
{"role": "$VAULT_USERROLE", "jwt": "$JWT"}
EOF

curl -s $VAULT_ADDR/v1/auth/kubernetes/login \
-H "Accept: application/json" \
-H "Content-Type:application/json" \
--data  @payload.json | jq . > tokendata.json

export VAULT_TOKEN=`cat tokendata.json | jq -r .auth.client_token`

echo VAULT_TOKEN = $VAULT_TOKEN

curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    -H "Accept: application/json" \
    --request GET \
    $VAULT_ADDR/v1/secret/data/${APP_NAME}/config > /vault/secrets//$VAULT_USERROLE.json

cat /vault/secrets/$VAULT_USERROLE.json | jq .data.data > /vault/secrets/secret-${APP_NAME}.json

cat /vault/secrets/secret-${APP_NAME}.json

#mkdir -p /vault/secrets/

./vault kv get secret/${APP_NAME}/config > /vault/secrets/secret-${APP_NAME}.properties

cat /vault/secrets/secret-${APP_NAME}.properties
