Create a project 

vault-instance

Install vault helm repo, update: 

helm repo add hashicorp https://helm.releases.hashicorp.com

helm repo update


Dev install of helm: 
helm install vault hashicorp/vault --set "global.openshift=true" --set "server.dev.enabled=true"

ensure pods running

exec to vault pod

`oc -n vault-instance exec -it vault-0 -- /bin/sh`

vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

## Secrets directly from vault
folder secrets-direct-from-vault

Creaet vault-demo project

create service account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp

oc create -f serviceaccount-webapp.yaml

Add webapp password: 
oc -n vault-instance exec -it vault-0 -- /bin/sh
vault kv put secret/webapp/config username="static-user" password="static-password"
vault kv get secret/webapp/config

Define read policy: 

`oc -n vault-instance exec -it vault-0 -- /bin/sh`
```
/ $ vault policy write webapp - <<EOF
path "secret/data/webapp/config" {
  capabilities = ["read"]
}
EOF
```

Create kubernetes authentication role: 

```
vault write auth/kubernetes/role/webapp \
    bound_service_account_names=webapp \
    bound_service_account_namespaces=vault-demo  \
    policies=webapp \
    ttl=24h
```

deploy webapp 

`oc apply -f secrets-direct-from-vault`

Verify that it works: 

```
oc exec \
    $(oc get pod --selector='app=webapp' --output='jsonpath={.items[0].metadata.name}') \
    --container app -- curl -s http://localhost:8080 ; echo
```


## Deploying secrets via annotations: 

Create and apply a service account: 
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: issues
```

exec into vault, create secret/issues/config 

`oc -n vault-instance exec -it vault-0 -- /bin/sh`

```
vault kv put secret/issues/config username="annotation-user" \
    password="annotation-password"

vault kv get secret/issues/config
```


Define policy for issues config: 

```
vault policy write issues - <<EOF
path "secret/data/issues/config" {
  capabilities = ["read"]
}
EOF
```


Create kubernetes authentication role for issues application: 
Make sure to use the 'vault-demo' namespace

```
vault write auth/kubernetes/role/issues \
    bound_service_account_names=issues \
    bound_service_account_namespaces=vault-demo \
    policies=issues \
    ttl=24h
```

deploy app

oc create -f deployment-issues.yaml

Verify vault: 
```
oc exec \
    $(oc get pod -l app=issues -o jsonpath="{.items[0].metadata.name}") \
    --container issues -- cat /vault/secrets/issues-config.txt ; echo
```


## Deploying secrets via an init container: 

Create and apply a service account: 
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: springvaultapp
```


vault kv put secret/springvaultapp/config password="password-in-vault"

```
vault policy write springvaultapp - <<EOF
path "secret/data/springvaultapp/config" {
  capabilities = ["read"]
}
EOF
```

```
vault write auth/kubernetes/role/springvaultapp \
    bound_service_account_names=springvaultapp \
    bound_service_account_namespaces=vault-demo \
    policies=springvaultapp \
    ttl=24h
```

Deploy application: 

`oc apply -f application-springvaultapp.yaml`

Check logs for the init container: 

`oc logs -f springvaultapp-x-xxxxx -c script-vault-adapter`

Check logs for the application: 

`oc logs -f springvaultapp-x-xxxxx`
