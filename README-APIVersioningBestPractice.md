# API Versioning Best Practice

> **Scope:** 本文件聚焦在「**應用層 + 治理層**」的 API 版本管理 — 同一個服務隨時間演進、API 越加越多時,如何在程式碼、Backstage catalog 與棄用流程中表達這件事。
>
> **不在範圍內:** 部署層工具(ArgoCD、Argo Rollouts、Helm)— 它們處理「image 怎麼安全推上 cluster」,跟 API 契約管理是相鄰但獨立的議題。文末會點出兩者的銜接點,但細節留給另一份文件。

---

## 0. 核心原則(一句話)

> **API version ≠ Image version。一個 image 同時 serve 多個 API version,版本退場由「時間 + 使用率」驅動,不是由「下一次部署」驅動。**

這個原則背後有一個假設:你的 client 不可能跟著你每次 deploy 同步升級。如果新 image 一上線就移除舊 API,那一秒所有還在用舊版的 client 都會壞掉。讓 image 累積 routes、讓客戶自己決定遷移時機,才是合理的解耦。

---

## 1. 七條準則

### 1.1 Additive model — 一個 image 同時 serve 全部 live 版本

```
python-app:a1b2c3 (這個 image)
├── /api/v1/*   ← 仍可工作(deprecated 但未退場)
├── /api/v2/*   ← production
└── /api/v3/*   ← 新加入
```

**不是** 「v3 image 取代 v2 image」**而是** 「v3 image 包含 v1 + v2 + v3 所有 routes」。

當 v1 真的要退場時,**靠新 image 把 v1 改回 410 Gone**(不是 404),而不是「砍掉一個 v2 image、換上一個 v3 image」。

### 1.2 URL path versioning(`/api/v1/`、`/api/v2/`)

業界 80% 以上的 public API 採用 path versioning,而非 header 或 query string:

| 方式 | 範例 | 評價 |
|---|---|---|
| **Path versioning** ✅ | `GET /api/v2/info` | 主流、debug 友善、cache/log/ingress 容易切版本 |
| Custom header | `X-API-Version: 2` + `GET /api/info` | 看似時髦,但 cache key 變複雜、log/metric 要額外抓 header |
| Accept media type | `Accept: application/vnd.acme.v2+json` | HATEOAS 派偏好,但工具支援差(Swagger UI 麻煩) |
| Query string | `GET /api/info?version=2` | **不要這樣做** — cache 行為怪、易被 strip |

### 1.3 Image tag 標的是「build」,不是「契約」

Image tag 應該是 commit 或 build 識別,**不能**等同於 API version。

```
✅ christseng89/python-app:a1b2c3            # git SHA — 一個 build
✅ christseng89/python-app:2026.05.28-3      # date-build

❌ christseng89/python-app:v3                # 跟 API version 重名 — 同一個 image 可能同時 serve v1+v2+v3
```

同一個 API v2 契約,可能會發 50 個 build(bug fix、效能、metric 增補,契約不變)。

### 1.4 Backstage — 一個 Component,多個 API entity

```
Component: python-app                               (對應「服務」實體 — 進程)
├── providesApis:
│   ├── API: python-app-api-v1   lifecycle: deprecated
│   ├── API: python-app-api-v2   lifecycle: production
│   └── API: python-app-api-v3   lifecycle: experimental
```

**Component 不要拆三個** (`python-app-v1`、`python-app-v2`、`python-app-v3`) — 對運維 / observability / oncall 來說只有一個服務。**契約** 才是版本化的概念,**服務** 不是。

`lifecycle` 是 Backstage 內建的 enum,UI 會自動加 badge:

| 值 | UI 顯示 | 用途 |
|---|---|---|
| `experimental` | 黃色 | 預覽,可能 breaking |
| `production` | 綠色 / 正常 | 主推 |
| `deprecated` | 灰色 + 警告 | 客戶端應遷出 |

### 1.5 用 RFC 9745 + RFC 8594 標頭做「程式可讀」的棄用通知

不要只靠 Markdown 文件人類去讀。Deprecated endpoint 在 response 加標頭:

```http
HTTP/1.1 200 OK
Content-Type: application/json
Deprecation: @1734393600
Sunset: Wed, 31 Dec 2025 23:59:59 GMT
Link: <https://example.com/api/v2/info>; rel="successor-version"
Link: <https://example.com/migration-v1-to-v2>; rel="deprecation"
```

| Header | RFC | 用途 |
|---|---|---|
| `Deprecation` | RFC 9745 | 「這個端點已標記棄用」,值可以是 `true` 或 Unix timestamp(@1734393600 = 宣告日期) |
| `Sunset` | RFC 8594 | 「預定的移除日期」(HTTP-date 格式) |
| `Link: rel="successor-version"` | RFC 5988 | 指向新版替代端點 |
| `Link: rel="deprecation"` | RFC 8288 | 指向遷移指南 |

Stripe / GitHub / Twilio 都這樣做。Client 端的 SDK / monitoring / proxy 可以自動攔截這些 header 警告開發者。

### 1.6 遷出窗口 ≥ 6 個月(理想 12 個月)

業界基準:

| 公司 | Deprecation → Sunset 窗口 |
|---|---|
| Stripe | 不主動移除舊版(client 鎖版本) |
| GitHub | 12 個月以上 |
| Google Cloud | 12 個月最低 |
| AWS | 12 個月以上 |
| Microsoft Graph | 24 個月最低 |

**內部 API** 可以縮到 3–6 個月,但 **要有明確日期**;不能「等大家用完再說」— 永遠等不到。

### 1.7 真正移除由「使用率」決定,不只看日期

宣告 Sunset 日期是 deadline,但 **實際刪除程式碼** 前要看數字:

```prometheus
http_requests_total{endpoint=~"/api/v1/.*"}
```

| Sunset 當天 v1 流量 | 行動 |
|---|---|
| < 1% | 安全移除 → 下一個 image release 把 v1 改成 410 Gone |
| 1% – 5% | 延 1–3 個月 + 個別聯繫剩下的 caller(用 access log + auth identity 找出來) |
| > 5% | 延 3–6 個月、把 `Deprecation` 升級成 `Warning` header、強化通知 |

完整退場路徑:

```
1. Sunset 日,流量 < 1%
2. 新 image 把 /api/v1/* 改成回 410 Gone(不是 404)+ migration link
3. 觀察 2 週,確認沒 client 哀號
4. 再下一個 image 才真的把 v1 程式碼刪掉
```

回 **410 Gone** 而不是 404,是有意義的訊號 — 410 = 「這資源以前在,現在刻意拿掉了」;404 = 「這資源從來沒在過」。Client 看到 410 才知道是棄用、要去看 migration guide。

---

## 2. 對應 python-app 的具體實作

### 2.1 程式碼結構

Flask blueprint 一個檔案一個版本:

```
python-app/src/
├── app.py                # 主入口,同時 register 三個 blueprint
├── api_v1.py             # Blueprint(url_prefix="/api/v1") — deprecated
├── api_v2.py             # Blueprint(url_prefix="/api/v2") — production
├── api_v3.py             # Blueprint(url_prefix="/api/v3") — experimental
└── deprecated_headers.py # @after_request middleware 統一加標頭
```

`app.py` 範例:

```python
from flask import Flask
from api_v1 import bp as v1_bp
from api_v2 import bp as v2_bp
from api_v3 import bp as v3_bp
from deprecated_headers import add_deprecation_headers

app = Flask(__name__)
app.register_blueprint(v1_bp)   # /api/v1/*
app.register_blueprint(v2_bp)   # /api/v2/*
app.register_blueprint(v3_bp)   # /api/v3/*

@app.after_request
def attach_deprecation_headers(response):
    return add_deprecation_headers(response)
```

`deprecated_headers.py` 範例:

```python
from flask import request

DEPRECATED_PREFIXES = {
    "/api/v1": {
        "sunset":    "Wed, 31 Dec 2025 23:59:59 GMT",
        "successor": "/api/v2",
        "guide":     "https://github.com/christseng89/python-app/blob/main/docs/migration-v1-to-v2.md",
    },
}

def add_deprecation_headers(response):
    for prefix, info in DEPRECATED_PREFIXES.items():
        if request.path.startswith(prefix):
            response.headers["Deprecation"] = "true"
            response.headers["Sunset"]      = info["sunset"]
            response.headers.add("Link", f'<{info["successor"]}>; rel="successor-version"')
            response.headers.add("Link", f'<{info["guide"]}>;     rel="deprecation"')
    return response
```

### 2.2 OpenAPI specs

```
python-app/
├── openapi-v1.yaml      # 對應 /api/v1
├── openapi-v2.yaml      # 對應 /api/v2
└── openapi-v3.yaml      # 對應 /api/v3
```

每份 spec 在 `info` 區段標 deprecation:

```yaml
# openapi-v1.yaml
openapi: 3.0.3
info:
  title: python-app API
  version: 1.0.0
  description: |
    **DEPRECATED** — will be removed on 2025-12-31.
    Migrate to [v2](./openapi-v2.yaml).
  x-deprecation:
    deprecated: true
    sunset: "2025-12-31"
    successor: "v2"
```

### 2.3 服務暴露 metadata 端點

讓 client 直接從 service 問版本資訊:

```python
@app.route("/version")
def version():
    return {
        "image":                  os.environ["IMAGE_TAG"],
        "git_sha":                os.environ["GIT_SHA"],
        "api_versions_supported": ["v1", "v2", "v3"],
        "api_versions_deprecated": ["v1"],
        "default_api_version":    "v2",
        "openapi": {
            "v1": "/openapi-v1.json",
            "v2": "/openapi-v2.json",
            "v3": "/openapi-v3.json",
        },
        "backstage_refs": {
            "v1": "api:default/python-app-api-v1",
            "v2": "api:default/python-app-api-v2",
            "v3": "api:default/python-app-api-v3",
        },
    }
```

Helm chart 在 Deployment 注入 env:

```yaml
env:
  - name: IMAGE_TAG
    value: {{ .Values.image.tag }}
  - name: GIT_SHA
    value: {{ .Values.image.gitSha | default .Values.image.tag }}
```

### 2.4 Backstage catalog

`python-app/catalog-info.yaml` 同時宣告 Component + 3 個 API entity:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: python-app
  annotations:
    github.com/project-slug: christseng89/MasterBackstageIdp
    backstage.io/kubernetes-id: python-app
    backstage.io/techdocs-ref: dir:.
spec:
  type: service
  owner: development
  lifecycle: production
  providesApis:
    - python-app-api-v1
    - python-app-api-v2
    - python-app-api-v3
---
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: python-app-api-v1
  description: v1 (3 endpoints) — deprecated, sunset 2025-12-31
  tags: [rest, python, v1, deprecated]
  links:
    - url: https://github.com/christseng89/python-app/blob/main/docs/migration-v1-to-v2.md
      title: Migration guide v1 → v2
spec:
  type: openapi
  lifecycle: deprecated
  owner: development
  definition:
    $text: ./openapi-v1.yaml
---
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: python-app-api-v2
  description: v2 (5 endpoints) — production
  tags: [rest, python, v2]
spec:
  type: openapi
  lifecycle: production
  owner: development
  definition:
    $text: ./openapi-v2.yaml
---
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: python-app-api-v3
  description: v3 (6 endpoints) — preview
  tags: [rest, python, v3, preview]
spec:
  type: openapi
  lifecycle: experimental
  owner: development
  definition:
    $text: ./openapi-v3.yaml
```

### 2.5 Kubernetes deployment labels(讓 Backstage K8s plugin 顯示)

Helm chart 的 Deployment template:

```yaml
metadata:
  labels:
    app.kubernetes.io/name:    python-app
    app.kubernetes.io/version: {{ .Values.defaultApiVersion }}    # 例如 "v2"
  annotations:
    api.example.com/default-version: {{ .Values.defaultApiVersion }}
    api.example.com/supported-versions: {{ .Values.supportedApiVersions | quote }}   # "v1,v2,v3"
    api.example.com/backstage-refs:    "api:default/python-app-api-v1,api:default/python-app-api-v2,api:default/python-app-api-v3"
```

`values-{env}.yaml` 各環境分別填:

```yaml
# values-dev.yaml
defaultApiVersion: v3                 # dev 主推預覽版
supportedApiVersions: "v1,v2,v3"

# values-staging.yaml
defaultApiVersion: v2
supportedApiVersions: "v1,v2,v3"

# values-prod.yaml
defaultApiVersion: v2
supportedApiVersions: "v1,v2,v3"
```

Backstage K8s plugin 會把這些 label/annotation 直接顯示在 component 頁面。

### 2.6 觀測

Prometheus metric 帶 `path_version` label:

```python
from prometheus_client import Counter

REQUEST_COUNT = Counter(
    "http_requests_total",
    "HTTP requests",
    ["path_version", "method", "status"],
)

def _path_version(path):
    if path.startswith("/api/v1"): return "v1"
    if path.startswith("/api/v2"): return "v2"
    if path.startswith("/api/v3"): return "v3"
    return "other"

@app.after_request
def count(response):
    REQUEST_COUNT.labels(_path_version(request.path), request.method, response.status_code).inc()
    return response
```

Grafana 面板看「v1 流量隨時間」是否真的在降。

---

## 3. 完整版本生命週期時間軸

```
Day 0     v3 開發中、branch
Day 30    v3 GA → release v3 image
          • catalog-info.yaml 新增 api-v3 entity (lifecycle: experimental)
          • image 同時 serve v1+v2+v3
          
Day 90    v3 穩定 → lifecycle: production
          • v2 改為 lifecycle: deprecated
          • v2 endpoint 開始回 Deprecation + Sunset header(sunset = Day 360)
          • 寄 email 通知所有已知 v2 client + 發 changelog

Day 90-330  監控 v2 流量曲線
          • Day 270(sunset 前 90 天):再寄一次提醒
          • Day 330(sunset 前 30 天):流量 > 5% 就延期

Day 360   Sunset day
          • 流量 < 1% → release 新 image,v2 endpoint 改回 410 Gone
          • 流量 > 1% → 延 90 天 + 個別聯繫

Day 360+  確認穩定後,下一個 release 把 v2 程式碼刪除
          • Backstage 刪除 api-v2 entity
          • Component 的 providesApis 移除 api-v2
```

---

## 4. Anti-patterns(常見錯誤)

| ❌ Anti-pattern | 為什麼錯 |
|---|---|
| 「v3 release 就把 v1 砍了」 | 沒給 client 遷移時間,線上事故的最大來源 |
| Image tag 跟 API version 同名(`python-app:v3.0.1`) | 一個 image 同時跑多版時這個命名直接打架 |
| 每個 API version 一個 Component / 一個 repo | repo 和 deploy 都被 3x 化,維護地獄 |
| 只在文件寫 deprecated,不發 header | 沒人主動讀文件;client 端 SDK 也無從自動偵測 |
| 沒有 sunset 日期,「慢慢看著辦」 | 永遠不會清掉,技術債滾雪球 |
| Breaking change 不 bump major | 等於沒有版本治理,client 全炸 |
| 刪 v1 時回 404 而不是 410 Gone | Client 以為是路徑寫錯,不會去查 migration guide |
| 把「跑著的 image 對應哪個 API version」寫進 catalog-info.yaml 的 annotation | 變成兩份事實(catalog vs 實際運行),易不一致 — 真相應該只在運行時(K8s label + service `/version` 端點) |

---

## 5. 與「部署層」工具的銜接點(out of scope,但要知道)

本文件只談應用層 + 治理層,但完整故事還包含部署層。**簡述如下:**

| 關注點 | 工具 | 解決什麼 |
|---|---|---|
| **API 契約管理** | 本文 | 「同一個 image 內有哪幾個 API 版本、哪個 deprecated、什麼時候 sunset」 |
| **GitOps 同步** | ArgoCD | 「git 上的 helm values 改了,自動同步到 cluster」 |
| **漸進式發布** | Argo Rollouts | 「換 image 時用 canary 5% → 25% → 100%、或 blue-green、出問題自動 rollback」 |

當你按本文件結構走 — 一個 image 同時 serve 多版 — 任何 image bug 都會同時影響三個版本的 client。所以**之後**導入 Argo Rollouts 做 canary 發布是合理的下一步,但**不是**本文件涵蓋的議題。本文件的所有準則,在你**還沒有** Argo Rollouts 的時候就可以全部落地。

---

## 6. 落地優先級

| 階段 | 工作 | 期待回報 |
|---|---|---|
| **Phase 1** | Flask blueprint 拆 v1/v2/v3 + URL path versioning | client 直接從 URL 看版本 |
| **Phase 1** | `Deprecation` + `Sunset` middleware | client SDK / proxy 可自動偵測棄用 |
| **Phase 1** | `/version` endpoint | 任何能打到 service 的人都能知道版本 |
| **Phase 2** | OpenAPI 拆 v1/v2/v3 + Backstage API entity × 3 + `lifecycle` | 開發者透過 Backstage catalog 找正確版本 |
| **Phase 2** | K8s deployment label / annotation | Backstage Kubernetes tab 顯示當下跑哪個 default API version |
| **Phase 3** | Prometheus `path_version` label + Grafana 流量面板 | 用數據而非感覺決定 sunset 是否能執行 |
| **Phase 3** | 寫 migration guide TechDocs | 客戶 self-service 升級 |
| **Phase 4** | 第一個 API 真的執行 sunset(回 410 Gone → 刪 code) | 驗證整套流程 |

Phase 1 可以一週內完成;Phase 2 大約一週;Phase 3 兩週;Phase 4 通常 6-12 個月之後才會走到。

---

## 7. 參考資料

- **RFC 9745** — The Deprecation HTTP Response Header Field
- **RFC 8594** — The Sunset HTTP Response Header Field
- **RFC 8288** — Web Linking(`Link` header 與 rel 類型)
- **OpenAPI 3.1** — `deprecated: true` 欄位與 `info.x-*` extensions
- **Backstage Catalog** — Component / API entity kinds、`lifecycle` enum、`providesApis` 關係
- **Stripe API Versioning** — <https://stripe.com/blog/api-versioning>(client-side 版本鎖定)
- **GitHub REST API Deprecation Policy** — <https://docs.github.com/en/rest/overview/api-versions>
