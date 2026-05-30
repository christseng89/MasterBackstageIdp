# Argo Rollouts (Argo CD plugin add-on)

Companion to `README-Recap3.2ArgoCD.md`. The `@backstage-community/plugin-argocd` views can also
render **Argo Rollouts** progressive-delivery state (canary/blue-green steps, `AnalysisRun`
results) when the Kubernetes plugin is allowed to read those custom resources. This is **optional**
— skip it unless you actually run Argo Rollouts in the cluster.

Prerequisite: the Argo CD plugin from Recap 3.2 is installed and working.

## 0. Install the Argo Rollouts

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm show values argo/argo-rollouts > rollouts-values.yaml

helm install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts \
  --create-namespace \
  -f python-app/charts/rollouts/values-rollouts.yaml

```

```cmd
notepad C:\Windows\System32\drivers\etc\hosts
  127.0.0.1 rollouts.test.com

ping rollouts.test.com
```

```bash
kubectl create ns demo
kubectl apply -n demo -f https://raw.githubusercontent.com/argoproj/argo-rollouts/master/docs/getting-started/basic/rollout.yaml
kubectl apply -n demo -f https://raw.githubusercontent.com/argoproj/argo-rollouts/master/docs/getting-started/basic/service.yaml

kubectl port-forward svc/argo-rollouts-dashboard -n argo-rollouts 3200:3200
```

http://rollouts.test.com:9080/rollouts
http://localhost:3200/rollouts/

## 1. Expose the custom resources to the Kubernetes plugin

The Argo CD views read Rollouts/AnalysisRuns through the Kubernetes plugin. Extend the existing
`kubernetes.customResources` block in **`app-config.local.yaml`** (you already have `applications`
there):

```yaml
kubernetes:
  customResources:
    - group: 'argoproj.io'
      apiVersion: 'v1alpha1'
      plural: 'applications'   # already present (Argo CD apps)
    - group: 'argoproj.io'
      apiVersion: 'v1alpha1'
      plural: 'rollouts'
    - group: 'argoproj.io'
      apiVersion: 'v1alpha1'
      plural: 'analysisruns'
```

## 2. Grant the service account read access

The cluster service account Backstage uses (`K8S_SA_TOKEN`) needs `get`/`list` on the new CRs.
The community plugin ships a prepared read-only ClusterRole that covers both the Kubernetes plugin
and Argo CD/Rollouts resources:

<https://raw.githubusercontent.com/backstage/community-plugins/main/workspaces/argocd/plugins/argocd/manifests/clusterrole.yaml>

```bash
kubectl apply -f https://raw.githubusercontent.com/backstage/community-plugins/main/workspaces/argocd/plugins/argocd/manifests/clusterrole.yaml
# then bind it to the ServiceAccount your K8S_SA_TOKEN belongs to, e.g.
kubectl create clusterrolebinding backstage-read-only \
  --clusterrole=backstage-read-only \
  --serviceaccount=<namespace>:<service-account-name>
```

If your existing Backstage Kubernetes ClusterRole already grants `rollouts` and `analysisruns`,
this step is a no-op.

## 3. Label the Rollout resources (per component)

So the views can map a Rollout to its GitOps application, the Rollout resources should carry:

```yaml
labels:
  app.kubernetes.io/instance: <argocd-application-name>
```

In this repo's GitOps pattern that label is already applied by the Helm charts / Argo CD, so
no manual change is usually needed.

## 4. Restart and verify

Restart the Backstage backend (`yarn start`) and open a component that runs a Rollout — the
Deployment views now show rollout strategy, step progress, and AnalysisRun status.

## Doing this in the scaffolder templates

To make every scaffolded app Rollouts-ready, the work is at the chart level, not in Backstage:

- Switch the Deployment in `charts/<app>/templates/` to an `argoproj.io/v1alpha1` **Rollout**
  (canary or blue-green strategy), keeping the existing `backstage.io/kubernetes-id` and
  `app.kubernetes.io/instance` labels.
- The `app-config.local.yaml` `customResources` + RBAC above are cluster-wide and only need to be
  applied once — they then cover all scaffolded apps automatically.

## Troubleshooting

- **No rollout data on the entity** — the `rollouts`/`analysisruns` entries are missing from
  `kubernetes.customResources`, or the service account lacks RBAC on them (step 1 / step 2).
- **`Forbidden` in the backend log for `rollouts.argoproj.io`** — the ClusterRole/binding in
  step 2 wasn't applied to the right ServiceAccount.
- **Rollout shows but isn't linked to the app** — the Rollout resource is missing the
  `app.kubernetes.io/instance: <argocd-application-name>` label (step 3).
