# Migration: API v1 → v2

API v1 is **deprecated** with a sunset date of **2025-12-31**. After that
date, the routes are scheduled to start returning `410 Gone`. This guide
explains how to move client code to v2.

## What changed?

v2 is a drop-in superset of v1 — the carry-over endpoints accept the
same inputs and return the same fields, with an extra `api_version`
field set to `"v2"` and an extra `deployed_on` field on `/info`. v2 then
adds two net-new endpoints (`/echo`, `/time`).

| v1 endpoint | v2 equivalent | Notes |
|---|---|---|
| `GET /api/v1/info` | `GET /api/v2/info` | Adds `deployed_on` field |
| `GET /api/v1/healthz` | `GET /api/v2/healthz` | Same shape, `status` is `"ok"` instead of `"up"` |
| `GET /api/v1/hostname` | `GET /api/v2/hostname` | Identical |

## How do I migrate?

1. Find every place your client emits a request whose path starts with
   `/api/v1/`. (A grep against your codebase + a check on your API gateway
   access logs usually catches everything.)
2. Replace `/api/v1` with `/api/v2` in the path.
3. If you parsed the `status` field from `/healthz`, expand your check
   from `status == "up"` to `status in ("up", "ok")` for the transition
   period, then drop `"up"` once v1 is gone.
4. Deploy and watch your monitoring for any 4xx coming back from v2.

## How do I know I haven't missed anything?

Two signals:

- **Backstage Kubernetes plugin** shows the running image's
  `app.kubernetes.io/version` label and `api.example.com/supported-versions`
  annotation. Both are sourced from the Helm chart so they stay
  in sync with the running pod.
- **The `Deprecation` / `Sunset` HTTP response headers** are emitted on
  every v1 response. If your client SDK or your reverse proxy logs these,
  you can tell exactly how many v1 calls still leave your perimeter.

## What happens on sunset day?

If `http_requests_total{path_version="v1"}` is < 1 % of total traffic on
the sunset date, the v1 routes are flipped to return `410 Gone` (not
`404`) in the next image release. A `410` includes the `Link` header
pointing here, so callers that don't read these docs first will at least
get a runtime breadcrumb.

If usage is still > 1 %, the sunset is pushed by 90 days and the
remaining callers are contacted individually using access-log identity.
