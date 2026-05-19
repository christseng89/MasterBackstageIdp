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

  backend:
    reading:
      allow:
        - host: raw.githubusercontent.com

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

