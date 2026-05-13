# Master Backstage IdP

## Python App

```cmd
git clone https://github.com/christseng89/backstage.git

git clone https://github.com/christseng89/python-app

cd python-app
uv init
pyenv global 3.12.10
pyenv local 3.12.10

uv sync
uv pip install -r requirements.txt

uv run main.py
    Hello from python-app!

uv run src\app.py
    http://127.0.0.1:5000
    http://127.0.0.1:5000/api/v1/info
    http://127.0.0.1:5000/api/v1/healthz    
```

## Docker

```cmd
cd python-app
docker build -t python-app:latest .
docker run -d -p 5000:5000 --name python-app python-app:latest 
    http://127.0.0.1:5000
    http://127.0.0.1:5000/api/v1/info
    http://127.0.0.1:5000/api/v1/healthz

docker exec -it python-app sh  
    apk add curl
    curl http://localhost:5000
    curl http://localhost:5000/api/v1/info
    curl http://localhost:5000/api/v1/healthz

docker logs python-app
docker stop python-app
docker rm python-app
```

```cmd
docker tag python-app:latest christseng89/python-app:latest
docker push christseng89/python-app:latest
```

## Kubernetes

```cmd
kubectl cluster-info
kubectl get nodes

kubectl get ns
kubectl get pod
kubectl get svc -A
kubectl get deployment -A
kubectl get ingress -A

kubectl get po -n ingress-nginx
```

## Deploy Python-App to Kubernetes

```cmd
kubectl apply -f k8s/python-app.yaml
kubectl get all
curl -iS http://localhost:5000
curl -iS http://localhost:5000/api/v1/info
curl -iS http://localhost:5000/api/v1/healthz

```

```cmd - DNS
notepad C:\Windows\System32\drivers\etc\hosts
    127.0.0.1       python-app.test.com

curl -iS http://python-app.test.com:5000
curl -iS http://python-app.test.com:5000/api/v1/info
curl -iS http://python-app.test.com:5000/api/v1/healthz    
```

```cmd - Delete Deployment/Service/Ingress
kubectl delete -f k8s/python-app.yaml
kubectl get all
```

## Helm Install Nginx Ingress Controller

```cmd
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace -f charts\nginx\values-nginx.yaml

kubectl get svc -n ingress-nginx | grep 9080
curl http://localhost:9080 

```

## Helm Install python-app

```cmd
docker tag christseng89/python-app:latest christseng89/python-app:v2
docker push christseng89/python-app:v2

helm install python-app k8s\charts\python-app --dry-run --debug
helm install python-app k8s\charts\python-app --set image.tag=v2

helm ls
kubectl get all 

curl http://python-app.test.com:9080
curl http://python-app.test.com:9080/api/v1/info
curl http://python-app.test.com:9080/api/v1/healthz

```

```cmd - Delete Helm Release
helm uninstall python-app

```

```cmd helm install with Namespace
helm install python-app k8s/charts/python-app --set image.tag=v2 -n python-app --create-namespace

helm ls -n python-app
kubectl get all -n python-app

curl http://python-app.test.com:9080
curl http://python-app.test.com:9080/api/v1/info
curl http://python-app.test.com:9080/api/v1/healthz

helm uninstall python-app -n python-app
```

## ArgoCD

<https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd>


```powershell
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 argocd.test.com"
```
 
```cmd
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace -f charts\argocd\values-argo.yaml

kubectl get ingress -n argocd
curl -iS http://argocd.test.com:9080

```

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    Yy9Z7X4V0fF4D0cU
```

```browser
http://argocd.test.com:9080
    Username: admin
    Password: Yy9Z7X4V0fF4D0cU
```

## ArgoCD Settings Repository

📌 How to Get a GitHub PAT (if you don't have one)

1. Go to → https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Note "MasterBackstageIdp"
4. Set scopes: ✅ repo (full control)
5. Click Generate token → Copy it immediately

Field                       Value
Connection Method           VIA HTTPS
Name                        MasterBackstageIdp
Project                     default
Repository URL              https://github.com/christseng89/MasterBackstageIdp.git
Username                    christseng89
Password                    <Your GitHub PAT>

## ArgoCD Application

Field               Value
Application Name    python-app ✅
Project Name        default ✅
Sync Policy         Manual 
Sync Options        ✅ Auto-Create Namespace
Enable Auto-Sync    ✅ Checked

Repository URL      https://github.com/christseng89/MasterBackstageIdp.git
Revision            main    ← 🔑 Any branch, tag, or commit
Path                python-app/k8s/charts/python-app ← 🔑 Key field

Cluster URL         https://kubernetes.default.svc
Namespace           python-app

VALUES FILES        values.yaml

=> Create => Sync => SYNCHRONIZE
    http://python-app.test.com:9080
    http://python-app.test.com:9080/api/v1/info 
    http://python-app.test.com:9080/api/v1/healthz
