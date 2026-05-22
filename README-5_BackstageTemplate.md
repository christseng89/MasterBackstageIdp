# Backstage Software Template

## Reference: Backstage 

- <https://backstage.io/docs/overview/what-is-backstage/>
- <https://backstage.io/docs/features/software-templates/>
- <https://github.com/christseng89/backstage-software-templates> # Template examples from Backstage's official repo
- <https://backstage.io/docs/features/software-templates/builtin-actions>

- <https://backstage.io/docs/features/software-templates/writing-templates>

## List Actions

A list of all registered actions can be found under /create/actions. For local development you should be able to reach them at <http://localhost:3000/create/actions>.

## Installation of Backstage Software Template

```bash
git clone https://github.com/christseng89/backstage-software-templates.git
cd backstage-software-templates/python-app
ls -l
    drwxr-xr-x 1 samfi 197609    0 May 21 18:11 template/
    -rw-r--r-- 1 samfi 197609 1689 May 21 18:24 template.yaml
```

## Edit app-config.local.yaml

```yaml app-config.local.yaml
catalog:
  rules:
    - allow: [Component, Template, System, API, Resource, Location]
  locations:
    # Absolute path inside the container (/app = volume mount root on host)
    ...
    - type: url
      target: https://github.com/christseng89/backstage-software-templates/blob/main/python-app/template.yaml
      rules:
        - allow: [Template]
```

## Setup GitHub repo python-app4

```bash

cd python-app
kubectl apply -f k8s/python-app.yaml
kubectl get all

cd ..

source .env

gh auth login
# From your home directory, a fresh VM, a CI runner, wherever
gh secret set DOCKERHUB_USERNAME --body $DOCKERHUB_USERNAME --repo christseng89/python-app4
gh secret set DOCKERHUB_TOKEN --body $DOCKERHUB_TOKEN --repo christseng89/python-app4
gh secret set ARGOCD_PASSWORD --body $ARGOCD_PASSWORD --repo christseng89/python-app4

gh secret list --repo christseng89/python-app4
gh secret set API_KEY --body "$KEY" --repo christseng89/python-app4
```
