# Recap

## 0 Preparation for .env variables

### 0.1 Configure Local DNS

The ingress rules expose hostnames `python-app.test.com` and `argocd.test.com`. Map them to your loopback so your browser can reach them through the local Nginx ingress.

PowerShell (as Administrator):

```powershell
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 python-app.test.com"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 argocd.test.com"
```

### 0.2 Create GitHub Personal Access Token

You'll need a GitHub Personal Access Token (PAT) so ArgoCD can read this repo.

1. Visit <https://github.com/settings/tokens> → **Generate new token (classic)**.
2. Name: `MasterBackstageIdp`, scopes: `repo`, `workflow` (full control).
3. Generate, then **copy immediately** — GitHub only shows it once.
4. Add it to your `.env` file as `GITHUB_PAT`.

### 0.3 Create DockerHub Access Token

At <https://hub.docker.com/settings/security>:

- Description: `MasterBackstageIdp`
- Expiration: None
- Access permissions: **Read & Write** (write is needed because the mirror workflow pushes new image repos like `christseng89/argocd-bin`)
- Copy the token and add it to your `.env` file as `DOCKERHUB_TOKEN`
- Your DockerHub username should also be in `.env` as `DOCKERHUB_USERNAME`

### 0.4 Register local BackstageIdp as a GitHub OAuth App

At <https://github.com/settings/developers>:

OAuth Apps → New OAuth App
    Application name:            MasterBackstageIdp
    Homepage URL:                http://localhost:3000
    Authorization callback URL:  http://localhost:7007/api/auth/github/handler/frame
→ Register application
→ Generate a new client secret (note: shown only once)

- Add the Client ID and Client Secret to your `.env` file as `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET`

### 0.5 Set Get k8s Service Account Token

```bash
kubectl create sa backstage -n kube-system
kubectl create clusterrolebinding backstage-view --clusterrole=view --serviceaccount=kube-system:backstage
kubectl -n kube-system create token backstage --duration=8760h
```

- Add the token value to your `.env` file as `K8S_SA_TOKEN`

### 0.6 Setup env vars

```bash
source .env
echo $K8S_SA_TOKEN
```

## 1. Install Nginx Ingress Controller

```bash
cd python-app
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f charts/nginx/values-nginx.yaml

kubectl get po -n ingress-nginx
kubectl get svc -n ingress-nginx

```

## 2 Install Python App

```bash
helm install python-app charts/python-app \
  --set image.tag=v2 -n python-app --create-namespace

kubectl get po -n python-app
kubectl get svc -n python-app

curl http://python-app.test.com:9080/api/v1/info

http://python-app.test.com:9080/
http://python-app.test.com:9080/api/v1/info

helm uninstall python-app -n python-app
kubectl delete ns python-app
cd ..

```

## 3 Install Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm upgrade --install argocd argo/argo-cd \
  -n argocd --create-namespace \
  -f charts/argocd/values-argo.yaml

kubectl get po -n argocd
kubectl get svc -n argocd

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

http://argocd.test.com:9080/  
```

- Add it to your `.env` file as `ARGOCD_PASSWORD`.

```bash
source .env
echo $ARGOCD_PASSWORD
```

## 4 Install Cert Manager, ARC and Deploy GitHub Self-Hosted Runner

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml
kubectl get po -n cert-manager

helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update actions-runner-controller
helm upgrade --install actions-runner-controller \
  actions-runner-controller/actions-runner-controller \
  --namespace actions-runner-system --create-namespace \
  --set authSecret.create=true \
  --set authSecret.github_token=$GITHUB_PAT

kubectl get po -n actions-runner-system
kubectl get cr -n actions-runner-system

kubectl apply -f python-app/runnerdeployment.yaml
kubectl get runners -n python-app

# Grant the runner pod read access to pods/deployments for CD diagnostics
kubectl apply -f python-app/k8s/runner-rbac.yaml

kubectl get clusterrole | grep python-app
kubectl get clusterrolebinding | grep python-app

kubectl get clusterrole -n actions-runner-system | grep python-app
kubectl get clusterrolebinding -n actions-runner-system | grep python-app

```

## 5 Set GitHub Secrets and Variables for the GitHub Workflows

```bash
source .env
gh auth login
# From your home directory, a fresh VM, a CI runner, wherever
gh secret set DOCKERHUB_USERNAME --body $DOCKERHUB_USERNAME --repo christseng89/MasterBackstageIdp
gh secret set DOCKERHUB_TOKEN --body $DOCKERHUB_TOKEN --repo christseng89/MasterBackstageIdp
gh secret set ARGOCD_PASSWORD --body $ARGOCD_PASSWORD --repo christseng89/MasterBackstageIdp
gh secret set GH_PAT --body $GITHUB_PAT --repo christseng89/MasterBackstageIdp

gh secret list --repo christseng89/MasterBackstageIdp

gh variable set ARGOCD_VERSION --body "v3.4.2" --repo christseng89/MasterBackstageIdp
gh variable set YQ_VERSION     --body "v4.44.3" --repo christseng89/MasterBackstageIdp
gh variable set KUBECTL_VERSION --body "v1.36.1" --repo christseng89/MasterBackstageIdp

gh variable list --repo christseng89/MasterBackstageIdp
```

### Run the GitHub Workflow

Github → MasterBackstageIdp → Settings → Actions → `mirror-cli-binaries` -> Run workflow
Github → MasterBackstageIdp → Settings → Actions → `cicd` → Run workflow

- http://argocd.test.com:9080/ → Login with username `admin` and the `ARGOCD_PASSWORD` from above → You should see the `python-app` application deployed by the `cicd` workflow
- http://python-app.test.com:9080/api/v1/info → You should see the JSON response from the Python app

## 6 Install MkDocs into Node Image and Run Backstage Locally

### Create a new Dockerfile that extends the base image with MkDocs installed:

```dockerfile
FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y python3 python3-pip curl jq nano make g++ && \
    pip install --break-system-packages mkdocs-techdocs-core
```

```bash
docker build -t node:24-bookwork-slim-pro .
docker tag node:24-bookwork-slim-pro christseng89/node:24-bookwork-slim-pro
docker push christseng89/node:24-bookwork-slim-pro
```

### `docker run` Backstage with MkDocs installed Image

```bash
cd backstage-app
mkdir techdocs-storage -p
source .env

docker run --rm --name backstage-local \
  -e GITHUB_TOKEN=$GITHUB_TOKEN \
  -e AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID \
  -e AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET \
  -e K8S_SA_TOKEN=$K8S_SA_TOKEN \
  --add-host=host.docker.internal:host-gateway \
  -p 3000:3000 -ti -p 7007:7007 \
  -v //d/development/MasterBackstageIdp/backstage-app://app \
  -v //d/development/MasterBackstageIdp/backstage-app/techdocs-storage://app/techdocs-storage \
  -v //d/development/MasterBackstageIdp/backstage-app/templates://app/templates:ro \
  -w //app christseng89/node:24-bookwork-slim-pro bash

  ## Wait

  cd backstage
  yarn start
  # ▶ Backstage running at http://localhost:3000
```

### Verify Python App in Backstage Catalog
- Open Backstage in your browser (http://localhost:3000).
-> Catalog -> CREATE -> REGISTER EXISTING COMPONENT
* URL: https://github.com/christseng89/MasterBackstageIdp/blob/main/python-app/catalog-info.yaml
-> ANALYZE -> IMPORT -> VIEW COMPONENT 

## Create a Python Project

- Open Backstage in your browser (http://localhost:3000).
-> Catalog -> CREATE -> `CHOOSE` TEMPLATE (Python flask template) -> Python Application -> USE TEMPLATE
* Component name: `python-app4` 
* Repository visibility: `Public (dev only)`
-> REVIEW

### Setup Python Project (python-app4)

```bash
git clone https://github.com/christseng89/python-app4.git
cd python-app4
cp ../.env .env
./setup.sh
```

- https://github.com/christseng89/python-app4/actions => python-app4-cicd => Run workflow
- http://argocd.test.com:9080/ → You should see the `python-app4` application deployed by the `python-app4-cicd` workflow
- http://python-app4-dev.test.com:9080/ → You should see the JSON response from the Python app
- http://python-app4-dev.test.com:9080/api/v1/info → You should see the JSON response from the Python app
- http://python-app4-dev.test.com:9080/api/v1/healthz → You should see the JSON response `{"status": "ok"}`
