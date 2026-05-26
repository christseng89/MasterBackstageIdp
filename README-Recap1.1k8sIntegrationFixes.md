# Backstage → Local Kubernetes Integration Fixes

Troubleshooting notes for getting the Backstage Kubernetes plugin to talk cleanly to a local Docker Desktop Kubernetes cluster.

Assumes the base wiring already in place per `README-Recap.md`:

- ServiceAccount `backstage` in namespace `kube-system`
- ClusterRoleBinding `backstage-view` → `view` ClusterRole
- Token in `.env` as `K8S_SA_TOKEN`
- `app-config.local.yaml` `kubernetes:` block pointing at `https://host.docker.internal:6443`
- Backstage container started with `-e K8S_SA_TOKEN=$K8S_SA_TOKEN` and `--add-host=host.docker.internal:host-gateway`

## Symptoms

On the entity page `http://localhost:3000/catalog/default/component/python-app/kubernetes`:

> **Warning: There was a problem retrieving Kubernetes objects**
>
> ```
> Cluster: docker-desktop
> Error fetching Kubernetes resource: '/apis/argoproj.io/v1alpha1/namespaces/python-app/applications', error: UNKNOWN_ERROR, status code: 403
> Error fetching Kubernetes resource: '/apis/metrics.k8s.io/v1beta1/namespaces/python-app/pods',       error: UNKNOWN_ERROR, status code: 403
> ```

Two independent issues:

1. The `view` ClusterRole does not include `argoproj.io` custom resources, so ArgoCD `Application` listing returns **403 Forbidden**.
2. Docker Desktop's Kubernetes does not ship with metrics-server. The aggregated API service `v1beta1.metrics.k8s.io` is referenced by Backstage's K8s plugin (for pod CPU/memory gauges) but no backing pod exists — returns **404** (or **000** during transitional states).

## Fix 1 — Grant the SA access to ArgoCD CRDs and metrics-server

Apply this single manifest from any shell with `kubectl` access to the cluster:

```bash
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: backstage-extra-view
rules:
  # ArgoCD Application custom resources
  - apiGroups: ["argoproj.io"]
    resources: ["applications", "appprojects", "applicationsets"]
    verbs: ["get", "list", "watch"]
  # Metrics Server (pod / node CPU + memory)
  - apiGroups: ["metrics.k8s.io"]
    resources: ["pods", "nodes"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: backstage-extra-view
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: backstage-extra-view
subjects:
  - kind: ServiceAccount
    name: backstage
    namespace: kube-system
EOF
```

Verify ArgoCD access from inside the running Backstage container:

```bash
docker exec -ti backstage-local bash

curl -sk -o /dev/null -w "argocd: %{http_code}\n" \
  -H "Authorization: Bearer $K8S_SA_TOKEN" \
  https://host.docker.internal:6443/apis/argoproj.io/v1alpha1/namespaces/python-app/applications
# expect: argocd: 200
```

## Fix 2 — Install metrics-server with `--kubelet-insecure-tls`

Docker Desktop's kubelet uses a self-signed certificate, so metrics-server needs the `--kubelet-insecure-tls` flag, otherwise scraping fails with `x509: cannot validate certificate`.

```bash
# Install
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch to accept the self-signed kubelet cert
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Wait for the rollout
kubectl -n kube-system rollout status deployment metrics-server
```

Wait ~30–60 seconds for the first scrape, then verify on the host:

```bash
kubectl top nodes
kubectl top pods -n python-app
```

Real CPU and memory values mean metrics-server is healthy.

From inside the Backstage container:

```bash
docker exec -ti backstage-local bash

curl -sk -o /dev/null -w "metrics: %{http_code}\n" \
  -H "Authorization: Bearer $K8S_SA_TOKEN" \
  https://host.docker.internal:6443/apis/metrics.k8s.io/v1beta1/namespaces/python-app/pods
# expect: metrics: 200
```

## Refresh Backstage

Hard-refresh the Kubernetes tab (Ctrl+F5):

`http://localhost:3000/catalog/default/component/python-app/kubernetes`

Expected end state:

- No yellow warning banner.
- Cluster card shows `1 pod` and `No pods with errors` (both green).
- Pod cards display CPU and memory usage gauges.
- A **Custom Resources** section appears below "Your Clusters" listing the ArgoCD `Application` for `python-app`.

## Diagnostic cheat sheet

If the warning banner reappears with new errors, expand it (click the caret) — Backstage prints the exact URL and status code. Map them like this:

| URL pattern | Status | Cause | Fix |
|---|---|---|---|
| `/apis/argoproj.io/...` | 403 | SA missing CRD permissions | Apply Fix 1 |
| `/apis/metrics.k8s.io/...` | 403 | SA missing metrics.k8s.io permissions | Apply Fix 1 |
| `/apis/metrics.k8s.io/...` | 404 | metrics-server not installed | Apply Fix 2 |
| `/apis/metrics.k8s.io/...` | 000 | metrics-server pod not ready / crashing | Check pod logs, confirm `--kubelet-insecure-tls` |
| `/api/v1/namespaces/.../pods` | 401 | `K8S_SA_TOKEN` expired or invalid | Re-create token: `kubectl -n kube-system create token backstage --duration=8760h` |
| `connect ECONNREFUSED` | — | Missing `--add-host=host.docker.internal:host-gateway` | Add the flag to `docker run` |

## Verification one-liners

Token still valid:

```bash
curl -sk -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $K8S_SA_TOKEN" \
  https://host.docker.internal:6443/api/v1/namespaces
# expect: 200
```

Metrics-server aggregated API is `Available`:

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
# expect AVAILABLE=True
```

Pod label matches the entity annotation:

```bash
kubectl get pods -A -l backstage.io/kubernetes-id=python-app
# expect at least one pod listed
```

Component annotation present:

```bash
grep -A4 annotations: python-app/catalog-info.yaml
# expect: backstage.io/kubernetes-id and backstage.io/kubernetes-namespace
```

## Notes

The `view` ClusterRole is intentionally narrow — it does not cover custom resources or aggregated APIs like `metrics.k8s.io`. The companion `backstage-extra-view` ClusterRole defined above keeps permissions minimal: read-only access to two specific API groups, nothing else.

For a local learning project, granting `cluster-admin` to the `backstage` SA is an acceptable shortcut:

```bash
kubectl create clusterrolebinding backstage-cluster-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:backstage
```

Do not do this on a real cluster. The `backstage-extra-view` ClusterRole is the right pattern for any non-local environment.

The K8S_SA_TOKEN created with `--duration=8760h` lasts one year. When it expires, regenerate with the same command, paste into `.env`, and restart the Backstage container.
