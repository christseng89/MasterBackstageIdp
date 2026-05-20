# Backstage Catalog Info for Python App

## Reference

<https://backstage.io/docs/overview/what-is-backstage>
<https://backstage.io/docs/features/software-catalog/>

## Backstage Catalog Descriptor Format

<https://backstage.io/docs/features/software-catalog/descriptor-format/>
<https://backstage.io/docs/features/software-catalog/descriptor-format/#kind-component>

<https://github.com/backstage/backstage/blob/master/packages/catalog-model/examples/acme/team-a-group.yaml>

```bash
docker exec -it 7716c20 bash
apt update && apt install -y nano
cd backstage/catalog/entities
touch groups.yaml
nano groups.yaml
nano users.yaml
```

```yaml groups.yaml
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: development
  description: Development Team
spec:
  type: team
  profile:
    # Intentional no displayName for testing
    email: development@example.com
    picture: https://api.dicebear.com/7.x/identicon/svg?seed=Fluffy&backgroundType=solid,gradientLinear&backgroundColor=ffd5dc,b6e3f4
  parent: backstage
  children: []
```

```yaml
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: christseng89
spec:
  profile:
    displayName: Christ Tseng
    email: samfire5200@gmail.com
    picture: https://api.dicebear.com/7.x/avataaars/svg?seed=Leo&backgroundColor=transparent
  memberOf: [development] # Change here
```

```bash
cd ../..
nano app-config.local.yaml
```

```yaml app-config.local.yaml
...
catalog:
  rules:
    - allow: [Component, System, API, Resource, Location]

  locations:
    # Absolute path inside the container (/app = volume mount root on host)
    - type: file
      target: /app/backstage/catalog/entities/users.yaml
      rules:
        - allow: [User]
    - type: file
      target: /app/backstage/catalog/entities/groups.yaml
      rules:
        - allow: [Group]

```

## Python App Catalog Descriptor

```yaml catalog-info.yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: python-app
  description: Python app that displays time.
  annotations:
    github.com/project-slug: christseng89/python-app
    backstage.io/techdocs-ref: dir:.
spec:
  type: service
  owner: development
  lifecycle: experimental
```

```bash
git add .
git commit -m "Add Backstage Catalog descriptor for Python app"
git push origin main
```

## Registering the Python App in Backstage Catalog

### 1. Restart Backstage
```bash
cd backstage-app
source .env
docker run --rm -e GITHUB_TOKEN=$GITHUB_TOKEN -e AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID -e AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET -p 3000:3000 -ti -p 7007:7007 -v //d/development/MasterBackstageIdp/backstage-app://app -w //app node:24-bookworm-slim bash

    cd backstage
    yarn start
        local: http://localhost:3000
    exit

```

### 2. Verify Python App in Backstage Catalog
- Open Backstage in your browser (http://localhost:3000).
-> Catalog -> CREATE -> REGISTER EXISTING COMPONENT
* URL: https://github.com/christseng89/MasterBackstageIdp/blob/main/python-app/catalog-info.yaml
-> ANALYZE -> IMPORT -> VIEW COMPONENT 

## Work with Kubernetes in Backstage

```bash
kubectl create sa backstage -n kube-system 
kubectl create clusterrolebinding backstage-view --clusterrole=view --serviceaccount=kube-system:backstage
kubectl -n kube-system create token backstage --duration=8760h
```

```bash .env
notepad .env 
  ...
  K8S_SA_TOKEN=eyJhbGciOi...
```

```tsx packages/app/src/modules/nav/Sidebar.tsx
      // Skipped items
      nav.take('page:search'); // Using search modal instead
      nav.take('page:kubernetes'); // 獨立 K8s 頁面不支援 — 只能當作實體分頁使用
      
```

```yaml python-app/catalog-info.yaml
metadata:
  name: python-app
  annotations:
    github.com/project-slug: christseng89/MasterBackstageIdp
    backstage.io/techdocs-ref: dir:.
    backstage.io/kubernetes-id: python-app
    backstage.io/kubernetes-namespace: python-app
...
```

```yaml app-config.local.yaml
kubernetes:
  serviceLocatorMethod:
    type: 'multiTenant'
  clusterLocatorMethods:
    - type: 'config'
      clusters:
        - name: docker-desktop
          url: https://host.docker.internal:6443
          authProvider: serviceAccount
          skipTLSVerify: true        # API cert is self-signed and not for host.docker.internal
          serviceAccountToken: ${K8S_SA_TOKEN}
  customResources:
    - group: 'argoproj.io'           # to see ArgoCD Application for python-app
      apiVersion: 'v1alpha1'
      plural: 'applications'

```

```bash
cd backstage-app
source .env
echo $K8S_SA_TOKEN

docker run --rm \
  -e GITHUB_TOKEN=$GITHUB_TOKEN \
  -e AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID \
  -e AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET \
  -e K8S_SA_TOKEN=$K8S_SA_TOKEN \
  --add-host=host.docker.internal:host-gateway \
  -p 3000:3000 -ti -p 7007:7007 \
  -v //d/development/MasterBackstageIdp/backstage-app://app \
  -w //app node:24-bookworm-slim bash

  apt-get update && apt-get install -y curl jq
  curl -sk -H "Authorization: Bearer $K8S_SA_TOKEN" \
    https://host.docker.internal:6443/api/v1/namespaces/python-app/pods | jq '.items[].metadata.name'
      #"python-app-55989d4d55-mslrc"
    cd backstage
    yarn start
        local: http://localhost:3000
    exit
``` 

## Verify Kubernetes Integration in Backstage

python-app\charts\python-app\templates\_helpers.tpl
```yaml
...
{{/*
Common labels
*/}}
{{- define "python-app.labels" -}}
helm.sh/chart: {{ include "python-app.chart" . }}
{{ include "python-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}
...
```

python-app\charts\python-app\values.yaml
```yaml
commonLabels:
  backstage.io/kubernetes-id: python-app
...
```

```bash
kubectl apply -f python-app/runnerdeployment.yaml
kubectl get runners
kubectl get po
```

http://argocd.test.com:9080/ => Sync python-app

```bash
kubectl get all,ingress -n python-app -l backstage.io/kubernetes-id=python-app
```

### Python App API Endpoint in Backstage
http://python-app.test.com:9080/
http://python-app.test.com:9080/api/v1/info
http://python-app.test.com:9080/api/v1/healthz

## Python App with API in Catalog

```yaml catalog-info.yaml
...
  links:
    - url: http://python-app.test.com:9080/
      title: Hello World
      icon: web
    - url: http://python-app.test.com:9080/api/v1/info
      title: Service Info
      icon: dashboard
    - url: http://python-app.test.com:9080/api/v1/healthz
      title: Health Check
      icon: techdocs
spec:
  type: service
  owner: development
  lifecycle: experimental
  providesApis:
    - python-app-api
---
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: python-app-api
  description: REST API exposed by python-app — greeting, info, and health endpoints.
  tags:
    - rest
    - python
    - flask
  links:
    - url: http://python-app.test.com:9080/api/v1/info
      title: Live /info endpoint
spec:
  type: openapi
  lifecycle: experimental
  owner: development
  definition:
    $text: ./openapi.yaml

```

python-app\openapi.yaml
```yaml
openapi: 3.0.3
info:
  title: python-app API
  description: Flask service that returns a greeting, current time/hostname, and a health check.
  version: 1.0.0
servers:
  - url: http://python-app.test.com:9080
    description: Local Docker Desktop via nginx ingress (port 9080)
paths:
  /:
    get:
      summary: Hello World
      description: Returns a simple greeting.
      responses:
        "200":
          description: Greeting
          content:
            text/html:
              schema:
                type: string
                example: Hello World!
  /api/v1/info:
    get:
      summary: Service info
      description: Returns current time, hostname, and a message.
      responses:
        "200":
          description: Service info
          content:
            application/json:
              schema:
                type: object
                properties:
                  time: { type: string, format: date-time }
                  hostname: { type: string }
                  message: { type: string }
                example:
                  time: "2026-05-20T10:30:00Z"
                  hostname: python-app-57c7f8c859-tcsdx
                  message: Hello from python-app
  /api/v1/healthz:
    get:
      summary: Liveness / readiness probe
      description: Returns 200 OK if the service is healthy.
      responses:
        "200":
          description: Healthy
          content:
            application/json:
              schema:
                type: object
                properties:
                  status: { type: string }
                example:
                  status: ok

```