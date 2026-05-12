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

## Helm Install python-app

```cmd
docker tag christseng89/python-app:latest christseng89/python-app:v2
docker push christseng89/python-app:v2

helm install python-app k8s/charts/python-app --dry-run --debug
helm install python-app k8s/charts/python-app --set image.tag=v2

helm list -n python-app
kubectl get all -n python-app

curl http://python-app.test.com:9080
curl http://python-app.test.com:9080/api/v1/info
curl http://python-app.test.com:9080/api/v1/healthz

```

```cmd - Delete Helm Release
helm uninstall python-app

```

```cmd helm install with Namespace
helm install python-app k8s/charts/python-app --set image.tag=v2 -n python-app --create-namespace
helm uninstall python-app -n python-app
```
