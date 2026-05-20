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
