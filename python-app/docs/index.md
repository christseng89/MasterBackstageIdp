# python-app

A Flask service that returns a greeting, current time/hostname, and a health check.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/` | Returns a `Hello World!` greeting |
| GET | `/api/v1/info` | Returns current time, hostname, and a message |
| GET | `/api/v1/healthz` | Liveness/readiness probe |

## How to access the app

The service is exposed via the nginx ingress controller running on Docker Desktop.

```bash
curl http://python-app.test.com:9080/
curl http://python-app.test.com:9080/api/v1/info
curl http://python-app.test.com:9080/api/v1/healthz
```
