# Integrating Hashicorp Vault with Openshift


Note, this is using a development instance of vault, nothing is stored persistently.  

The vault server instance is create in the 'vault-instance' project. 

The applications will be deployed in the 'vault-demo' project. 


## Installing vault

Create the project vault-instance

Install vault helm repo, then update: 

```
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```


Install the development version of helm:
```
helm install vault hashicorp/vault --set "global.openshift=true" --set "server.dev.enabled=true"
```

Start a shell inside the vault instance: 

`oc -n vault-instance exec -it vault-0 -- /bin/sh`

Now we'll enable kubernetes auth: 

`oc -n vault-instance exec -it vault-0 -- /bin/sh`

```
vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```


## Secrets directly from vault
folder secrets-direct-from-vault

Create the project 'vault-demo'

create a service account for the application: 

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp
```

`oc create -f serviceaccount-webapp.yaml`

Add webapp password: 

Start a shell in the vault instance: 

`oc -n vault-instance exec -it vault-0 -- /bin/sh`

Create and check the secret: 

```shell
vault kv put secret/webapp/config username="static-user" password="static-password"
vault kv get secret/webapp/config
```

Define the policy allowing the secret to be read: 

`oc -n vault-instance exec -it vault-0 -- /bin/sh`
```
/ $ vault policy write webapp - <<EOF
path "secret/data/webapp/config" {
  capabilities = ["read"]
}
EOF
```

Create the kubernetes authentication role.  This ties the application service account with the policy used to read the secret: 

```
vault write auth/kubernetes/role/webapp \
    bound_service_account_names=webapp \
    bound_service_account_namespaces=vault-demo  \
    policies=webapp \
    ttl=24h
```

Deploy the webapp 

`oc apply -f secrets-direct-from-vault`

Verify that it works: 

```
oc exec \
    $(oc get pod --selector='app=webapp' --output='jsonpath={.items[0].metadata.name}') \
    --container app -- curl -s http://localhost:8080 ; echo
```


## Deploying secrets via annotations: 
Operate from folder secrets-via-annotations


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

Deploy the issues application: 

`oc create -f deployment-issues.yaml`

Verify that the secret was deployed to the issues application: 
```
oc exec \
    $(oc get pod -l app=issues -o jsonpath="{.items[0].metadata.name}") \
    --container issues -- cat /vault/secrets/issues-config.txt ; echo
```


## Getting secrets via an init container: 

Note that for this example, we need an init container.  The images for the application and init container have already been built. 

If, however, you need to build these, do the following: 

### Building the Java application 
cd to springvaultapp

`./buildimage.sh && ./pushimage.sh`


### Building init container image: 
Note that to use the init container pattern, we need to create a docker image with a script that will pull secrets from vault.

cd vault-initadapter

`./buildpushimage.sh`


### Deploying the initContainer-enabled Spring Boot application

Create and apply a service account: 
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: springvaultapp
```

`oc create -f serviceaccount-springvaultapp.yaml`


Exec into vault instance: 

`oc -n vault-instance exec -it vault-0 -- /bin/sh`

Create the secret: 

`vault kv put secret/springvaultapp/config password="password-in-vault"`

Create a vault policy to allow the springvaultapp secret to be read: 

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

Let's examine the DeploymentConfig: 

```yaml
apiVersion: v1
kind: DeploymentConfig
metadata:
  name: springvaultapp
spec:
  triggers:
    -
      type: ConfigChange
  replicas: 1
  template:
    metadata:
      labels:
        app: springvaultapp
    spec:
      serviceAccountName: springvaultapp
      initContainers:
      - name: script-vault-adapter
        image: docker.io/sholly/vault-initadapter:0.0.1
        imagePullPolicy: Always
        env:
        - name: "APP_NAME"
          value: springvaultapp
        - name: "VAULT_ADDR"
          value: "http://vault.vault-instance.svc:8200"
        - name: "VAULT_USERROLE"
          value: springvaultapp
        volumeMounts:
        - name: secret-volume
          mountPath: /vault/secrets
      containers:
        - name: springvaultapp
          image: docker.io/sholly/springvaultapp:0.0.1
          imagePullPolicy: Always
          env:
          - name: "APP_NAME"
            value: springvaultapp
          - name: "VAULT_USERROLE"
            value: springvaultapp
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 3
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 3
          volumeMounts:
          - name: secret-volume
            mountPath: /vault/secrets
      volumes:
      - name: secret-volume
        emptyDir: {}
```

Deployed applications *MUST* use the serviceaccount configured to talk to vault. 

Deploy the application: 

`oc apply -f springvaultapp/application-initcontainer.yaml`

If the secret is read properly, the init container logs will show the secret getting written.  The application logs
will show the application reading the secret.  

Check logs for the init container: 

`oc logs -f springvaultapp-x-xxxxx -c script-vault-adapter`

Check logs for the application: 

`oc logs -f springvaultapp-x-xxxxx`


## Injecting secrets via annotations.  

This method uses annotations in the DeploymentConfig, which will 
automatically inject a Vault sidecar.  

This example reuses the 'springvaultapp' serviceaccount, as well as the vault data and policy from the
previous step. 


Examine the deploymentconfig: 

```yaml
apiVersion: v1
kind: DeploymentConfig
metadata:
  name: springvaultann
spec:
  triggers:
    -
      type: ConfigChange
  replicas: 1
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: 'true'
        vault.hashicorp.com/role: 'springvaultapp'
        vault.hashicorp.com/agent-inject-secret-secret-springvaultann.properties: 'secret/data/springvaultapp/config'
        vault.hashicorp.com/agent-inject-template-secret-springvaultann.properties: |
          {{- with secret "secret/data/springvaultapp/config" -}}
          password    {{ .Data.data.password }}
          {{- end -}}
      labels:
        app: springvaultann
    spec:
      serviceAccountName: springvaultapp
      containers:
        - name: springvaultann
          image: docker.io/sholly/springvaultapp:0.0.1
          imagePullPolicy: Always
          env:
          - name: "APP_NAME"
            value: springvaultann
          - name: "VAULT_USERROLE"
            value: springvaultapp
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 3
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 3
```

Deploy the application: 

`oc apply -f springvaultapp/application-annotated.yaml`

Once again, we can check the logs to make sure the secret was read successfully.  Note that now we should have not only init container logs, but the Vault sidecar will log that it is writing secrets.  We can also check the application logs to verify that the secret was read successfully.  