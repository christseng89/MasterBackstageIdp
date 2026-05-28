# ${{values.app_name}}

A Python Flask service demonstrating the **additive multi-API-version** pattern:
the same image simultaneously serves three API versions, with v1 marked
deprecated, v2 production, and v3 experimental.

## Where can I reach it?

| Env | URL |
|---|---|
| dev | <http://${{values.app_name}}-dev.test.com:9080> |
| staging | <http://${{values.app_name}}-staging.test.com:9080> |
| prod | <http://${{values.app_name}}-prod.test.com:9080> |

## Discovering which API version is live

Any client can hit `/version` to see what the running image supports:

```bash
curl http://${{values.app_name}}-dev.test.com:9080/version
```

Response example:

```json
{
  "image": "a1b2c3",
  "git_sha": "a1b2c3...",
  "api_versions_supported": ["v1", "v2", "v3"],
  "api_versions_deprecated": ["v1"],
  "default_api_version": "v3",
  "openapi": { "v1": "/openapi-v1.yaml", "v2": "/openapi-v2.yaml", "v3": "/openapi-v3.yaml" },
  "backstage_refs": {
    "v1": "api:default/${{values.app_name}}-api-v1",
    "v2": "api:default/${{values.app_name}}-api-v2",
    "v3": "api:default/${{values.app_name}}-api-v3"
  }
}
```

The Kubernetes Deployment also carries the default version as a label so
the Backstage Kubernetes plugin shows it directly:

```bash
kubectl get deploy -n ${{values.app_name}}-prod -L app.kubernetes.io/version
```

## Quick reference

See [API versions](api-versions.md) for the full endpoint list and the
[v1 → v2 migration guide](migration-v1-to-v2.md) if you're still on v1.
