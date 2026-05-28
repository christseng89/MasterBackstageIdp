# Setup Github Organization (參考用)

> **目前實際採用的路線:per-repo secrets/variables + per-repo runner**
>
> Scaffolded repo 仍建立在個人帳號 `christseng89/<app>` 底下,每個 repo 自己
> 透過 `backstage-app/templates/python-app/template/setup.sh` 設定 4 個 secrets、
> 3 個 variables,以及自己的 per-repo ARC `RunnerDeployment`(`spec.template.spec.repository`)。
> 本文件保留 org-level 的做法作為**未來參考**,並列出真要切到 org 模式時必須連帶
> 修改的所有檔案。
>
> 另外 root folder 多了一個 [`github-org-runner/`](./github-org-runner/) 資料夾,
> 提供 **org-level self-hosted runner** 的測試用 YAML — 不影響任何 template,可獨立
> 套用驗證 org runner 是否能跑起來,詳見本文 §5。

---

## 1. Create a GitHub Organization

Github → New Organization (free) → 

- Organization name: `intelligent-ltd`
- Contact email: `samfire5200@gmail.com`
- My personal account: `christseng89 (Chris Tseng)`

→ Next → Search by username, full name or email address

- christseng889 Samfire5202
- samfire5201@gmail.com (Invite by email)

→ Complete setup → Follow

## 2. Test gh commands

```bash
gh auth login
gh repo list intelligent-ltd --limit 10

gh auth refresh -h github.com -s admin:org
gh auth status
    github.com
    ✓ Logged in to github.com account christseng89 (keyring)
    - Active account: true
    - Git operations protocol: https
    - Token: gho_************************************
    - Token scopes: 'admin:org', 'gist', 'repo', 'workflow'

gh variable set JAVA_VERSION --org intelligent-ltd --body "21"
gh secret set TEST_SECRET --org intelligent-ltd --visibility all

gh secret list   --org intelligent-ltd
gh variable list --org intelligent-ltd
```

## 3. Org-level secrets/variables bootstrap script

Root 提供了一支 `setup-org.sh`,**目前未啟用**,作為日後若要把 secrets/variables
集中到 org 時的現成工具。

### 3.1 準備 `.env`

```bash
# Required by setup-org.sh (secrets section)
DOCKERHUB_USERNAME=your-dockerhub-username
DOCKERHUB_TOKEN=your-dockerhub-token
ARGOCD_PASSWORD=your-argocd-admin-password
GITHUB_PAT=your-github-personal-access-token   # needs admin:org

# Optional — overrides defaults in setup-org.sh (variables section)
ARGOCD_VERSION=v3.4.2
YQ_VERSION=v4.44.3
KUBECTL_VERSION=v1.36.1
```

> **PAT scopes required:** `admin:org`, `repo`, `workflow`。
> 沒有 `admin:org`,`gh secret set --org` 與 `gh variable set --org` 都會 403。

### 3.2 執行

```bash
bash setup-org.sh                        # secrets + variables (both)
bash setup-org.sh --secrets-only         # only secrets
bash setup-org.sh --variables-only       # only variables (defaults OK, .env 可省)
```

> **覆寫行為:** 每次執行都會以 `.env` 的值覆寫 org-level 對應的 secret/variable。
> Token 輪替或版本升級後重跑即可 — 不需要任何額外 flag。

**Step 1 — Org-level secrets**(`--visibility all`):

| Secret | Used by |
|--------|---------|
| `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` | CI image push + mirror workflow |
| `ARGOCD_PASSWORD` | All CD jobs (`argocd login`) |
| `GH_PAT` | CD job git push-back + ArgoCD repo registration |

**Step 2 — Org-level variables**(`--visibility all`):

| Variable | Default | Used by |
|----------|---------|---------|
| `ARGOCD_VERSION`  | `v3.4.2`  | All CD workflows + mirror |
| `YQ_VERSION`      | `v4.44.3` | `cicd.yaml` + mirror |
| `KUBECTL_VERSION` | `v1.36.1` | All CD workflows + mirror |

不需要 idempotent 判斷 — 每次執行都直接覆寫,讓 `.env` 永遠是單一真相來源。

> **Bumping versions:** 在 CD 用到新版本之前,先在任一個 repo 跑
> `mirror-cli-binaries.yaml` workflow 把對應 image 推上 Docker Hub。

### 3.3 驗證

```bash
gh secret list   --org intelligent-ltd
gh variable list --org intelligent-ltd
```

---

## 4. 若真要切換到 org 模式 — Template folder 必須修改的檔案清單

GitHub 的 secret/variable 範圍**嚴格按 owner namespace 切分**:`christseng89`
(個人)與 `intelligent-ltd`(org)是兩套獨立的命名空間。Scaffolded repo 必須
**實際建立在 org 底下**,才能繼承 org-level 的 secrets/variables。

> **`christseng89` 在不同檔案裡有兩種意義 — 切換前務必分清楚:**
>
> - **GitHub owner**(`github.com/christseng89/...`、`--repo christseng89/...`、`github.com?owner=christseng89`)— secrets/variables namespace 綁這個,切到 org 時**必須改**成 `intelligent-ltd`。
> - **Docker Hub namespace**(`christseng89/<app>:tag`、`christseng89/argocd-bin`、`christseng89/yq-bin`、`christseng89/kubectl-bin`)— 是你的 Docker Hub 帳號,**跟 GitHub org 完全無關**,留著不動。除非你打算同時把 Docker Hub 也搬到 organization plan,否則改了會直接 push/pull 失敗。
>
> 下表「必改」**只列 GitHub owner 用法**。所有 Docker Hub image 引用都收在 4.2「不受影響的檔案」。

### 4.1 必改檔案

| # | 檔案 | 行號 | 目前 | 改成 |
|---|------|------|------|------|
| 1 | `backstage-app/templates/python-app/template.yaml` | 57 | `repoUrl: github.com?owner=christseng89&repo=${{ parameters.component_id }}` | `repoUrl: github.com?owner=intelligent-ltd&repo=${{ parameters.component_id }}` |
| 2 | `backstage-app/templates/python-app/template/setup.sh` | 14 | `REPO="christseng89/${{values.app_name}}"` | `REPO="intelligent-ltd/${{values.app_name}}"` |
| 3 | `backstage-app/templates/python-app/template/setup.sh` | 90–111 | Step 2 / Step 3(repo-level secrets/variables) | 整段刪除 — org 已提供 |
| 4 | `backstage-app/templates/python-app/template/runnerdeployment.yaml` | 20 | `repository: christseng89/${{values.app_name}}` | `repository: intelligent-ltd/${{values.app_name}}` 或改用 `organization: intelligent-ltd` 走 org-level runner |
| 5 | `backstage-app/templates/python-app/template/catalog-info.yaml` | 7 | `github.com/project-slug: christseng89/${{ values.app_name }}` | `github.com/project-slug: intelligent-ltd/${{ values.app_name }}` |
| 6 | `backstage-app/templates/python-app/template/mkdocs.yaml` | 3 | `repo_url: https://github.com/christseng89/${{values.app_name}}` | `repo_url: https://github.com/intelligent-ltd/${{values.app_name}}` |
| 7 | `backstage-app/templates/python-app/template/README.md` | 12, 39, 72, 212–215, 229–231 | Tree header、clone URL、setup.sh 說明段、Appendix Step 2–3 的 `--repo christseng89/${{values.app_name}}` | 全數替換成 `intelligent-ltd/${{values.app_name}}` |

> 同檔內 line 126(`builds christseng89/${{values.app_name}}:<sha>` — pipeline 流程示意)是 **Docker Hub image** 引用,不需改。

### 4.2 不受影響的檔案

**A. 與 GitHub owner 無關的既有檔案**

- `python-app/catalog-info.yaml` / `python-app4/catalog-info.yaml` — `github.com/project-slug` 指向的是這個學習用 monorepo (`christseng89/MasterBackstageIdp`),scaffolded repo 搬家不影響它們。
- Backstage 主機本身的 `app-config.*.yaml` — 只要 GitHub integration token 對 `intelligent-ltd` 與 `christseng89` 兩個 namespace 都有讀取權,catalog 可同時拉兩邊。

**B. Docker Hub image 引用(christseng89 是 Docker Hub 帳號,不是 GitHub owner)**

| 檔案 | 行號 | 內容 |
|------|------|------|
| `template/.github/workflows/${{values.app_name}}-cicd.yaml` | 25, 97–98, 123, 155, 198 | `IMAGE_NAME: christseng89/${{values.app_name}}` + `argocd-bin` / `yq-bin` / `kubectl-bin` 拉取 |
| `template/.github/workflows/${{values.app_name}}-staging-cd.yaml` | 87, 121 | `christseng89/kubectl-bin`、`christseng89/argocd-bin` |
| `template/.github/workflows/${{values.app_name}}-prod-cd.yaml` | 87, 121 | `christseng89/kubectl-bin`、`christseng89/argocd-bin` |
| `template/.github/workflows/mirror-cli-binaries.yaml` | 78, 81, 104, 107, 131, 134, 163–165 | push target 與 job summary 上的 mirror image tag |
| `template/setup.sh` | 119 | `--skip-mirror` 提示訊息中的 `christseng89/argocd-bin` 等 |
| `template/README.md` | 126 | pipeline 流程示意中的 `christseng89/${{values.app_name}}:<sha>` |

### 4.3 切換流程順序

1. 在 `intelligent-ltd` 建好 org、`gh` 取得 `admin:org` scope
2. 跑 root 的 `bash setup-org.sh`(填好 root 的 `.env`)
3. 改上面 #1–#7 七個檔案(只改 GitHub owner 用法,Docker Hub image 引用全數保留)
4. 用更新後的 template 從 Backstage scaffold 一個測試 repo,驗證 workflow 能讀到 org 的 secrets/variables

在那之前,本 repo 仍維持 per-repo 設定,新 scaffold 的 repo 每次都跑
template 的 `setup.sh` 把 secrets/variables 設在自己的 repo 上即可。

---

## 5. Org-level self-hosted runner(獨立測試,不影響 templates)

Root folder 提供 [`github-org-runner/`](./github-org-runner/) 一份完整 YAML,
讓你可以在不動到任何 template 的前提下,在 `intelligent-ltd` org 註冊一組**共用的**
ARC self-hosted runner,**驗證 org-level runner 是否能正常運作**。

### 5.1 為什麼分開放,不直接改 templates?

| | per-repo runner(現狀) | org-level runner(本資料夾) |
|---|---|---|
| 註冊範圍 | `repository: christseng89/<app>` | `organization: intelligent-ltd` |
| 由哪個檔案建立 | scaffolded repo 的 `runnerdeployment.yaml`(由 setup.sh 套用) | `github-org-runner/org-runner.yaml`(手動 `kubectl apply`) |
| Workflow `runs-on:` | `self-hosted`(預設行為,匹配同一 repo 的 per-repo runner) | `[self-hosted, org-runner]`(用自訂 label 顯式選 org runner) |
| 影響範圍 | 只該 repo 的 workflow 用得到 | org 內任何 repo 都能用 |
| 何時用 | 預設;每個 scaffolded repo 自動有 | 測試 / 多個 repo 想共用一組 runner pool 時 |

**兩者可以同時存在** — workflow 寫 `runs-on: self-hosted` 還是會匹配到 per-repo runner;
要打到 org runner 必須明寫 `[self-hosted, org-runner]`。所以加 org runner **不會**讓現有
template 的 CI/CD 流程變動。

### 5.2 內含什麼

| 檔案 | 用途 |
|---|---|
| `github-org-runner/org-runner.yaml` | 一次 apply 三個資源:`ServiceAccount`、`RunnerDeployment`(`organization:` scope)、`HorizontalRunnerAutoscaler`(`minReplicas: 1` / `maxReplicas: 5`) |
| `github-org-runner/webhook-server.yaml` | **可選**。ARC webhook server 的 standalone Deployment + Service,讓 HRA 收到 `workflow_job` event 後真正 scale up 到 maxReplicas;只有非 Helm 安裝時需要 apply,Helm 用戶 `helm upgrade ... --set githubWebhookServer.enabled=true` 即可 |
| `github-org-runner/README.md` | 套用步驟、驗證指令、workflow 範例、teardown 步驟、webhook server + ngrok / cloudflared 完整設定 |

### 5.3 前置 — PAT scope 必須含 `admin:org`

ARC controller 用的 PAT 預設只有 `repo`+`workflow` scope(夠 repo-level runner 註冊用),
但 org-level runner 需要 `admin:org` 才能呼叫 `POST /orgs/<org>/actions/runners/registration-token`。
沒升級就 apply,RunnerDeployment 會卡在 `DESIRED=1, AVAILABLE=0` 永遠拉不出 pod。

**最簡單做法:直接擴充既有 PAT 的 scope,不用換 token 字串**

```
1. 開 https://github.com/settings/tokens
2. 點 ARC controller 現在用的那顆 PAT
3. 中段 scope 清單,勾上 admin:org(會自動含 write:org / read:org / manage_runners:org)
4. 頁面最下方按 Update token
```

PAT 字串完全不變 → K8s secret 不用碰 → 只要重啟 controller 讓它立刻重試即可:

```bash
kubectl -n actions-runner-system rollout restart deployment
kubectl -n actions-runner-system rollout status deployment
```

> 只有當 PAT 已過期或被 revoke 時才需要產新 token + 重灌 secret。完整指令仍寫在
> `github-org-runner/README.md` 的 Prerequisites 章節。

### 5.4 套用 + 驗證

```bash
# 套用
kubectl apply -f github-org-runner/org-runner.yaml

# 確認 RunnerDeployment AVAILABLE=1 + pod 跑起來
kubectl get runnerdeployment,pod -n github-runners | grep intelligent-ltd

# Runner log 看到 "Listening for Jobs"
POD=$(kubectl get pods -n github-runners --no-headers | grep '^intelligent-ltd-' | awk '{print $1}' | head -1)
kubectl logs -n github-runners "$POD" -c runner --tail=30 \
  | grep -iE 'gitHubUrl|organization|Connected|Listening'

# GitHub API 確認(Git Bash 開頭不能帶斜線 — MSYS 會把它當路徑改寫)
gh api orgs/intelligent-ltd/actions/runners \
  --jq '.runners[] | {name, status, labels: [.labels[].name]}'

# UI:https://github.com/organizations/intelligent-ltd/settings/actions/runners
```

### 5.5 怎麼從 workflow 用它

在 `intelligent-ltd` 底下任一個 repo 加一個 job:

```yaml
jobs:
  test-org-runner:
    runs-on: [self-hosted, org-runner]
    steps:
      - run: |
          echo "Running on $(hostname) — org-level runner"
```

注意:**只有顯式寫 `org-runner` label 才會路由到這顆**,所以不用擔心既有 workflow
(只寫 `runs-on: self-hosted` 的)被搶走 — 那些仍會匹配同一 repo 的 per-repo runner。

### 5.6 完成測試後拆掉

```bash
kubectl delete -f github-org-runner/org-runner.yaml
```

如果剛剛只是為了測試 org runner 才升級 PAT 加 `admin:org` scope,測完想收回權限,
回到 <https://github.com/settings/tokens> 點該 PAT、取消勾 `admin:org`、Update token
即可。PAT 字串照樣不變,per-repo runner 的 `repo`+`workflow` 權限不會受影響。

### 5.7 進階:開啟 webhook server,讓 maxReplicas 真正生效

預設情況下 `org-runner.yaml` 內的 HRA 雖然有 `scaleUpTriggers`、`maxReplicas: 5`,
但**沒設 webhook 的話 ARC 收不到 `workflow_job` event**,池子永遠卡在 `minReplicas`
那一顆,其他 jobs 在 GitHub queue 等待。

> **本 repo 目前的 cluster 是 Helm 安裝**(`actions-runner-controller-0.23.7` /
> app v0.27.6 — 用 `helm list -A | grep actions-runner-controller` 驗證得到),
> 所以走下面 4 步驟時 **絕對不要 `kubectl apply -f github-org-runner/webhook-server.yaml`** —
> Helm 已經管理同一份 Deployment,再 apply 會撞起來。改用 `helm upgrade ... --set
> githubWebhookServer.enabled=true` 一行啟用即可,完整指令(含 `--version 0.23.7`
> 鎖版本)寫在 sub-folder README 的 Path A 段落。
> `webhook-server.yaml` 只是備用,留給未來「ARC 改用 raw kubectl manifest 重裝」
> 的情境參考。

對 Docker Desktop 本地測試夠用,但要驗證 maxReplicas 真的 work 就需要四步:

1. **裝 webhook server**(本環境:Helm 一行 upgrade。非 Helm 環境才 apply `webhook-server.yaml`)
2. **產 webhook secret** + 建 K8s secret(Helm `--set` 一併處理)
3. **用 ngrok / cloudflared 把本地 webhook 暴露給 GitHub**
4. **GitHub org settings → Webhooks → Add webhook** 設好 payload URL / secret / 勾 `Workflow jobs` event

完整步驟、指令、所有平台對應(含 GitHub UI 截圖必填欄)寫在
[`github-org-runner/README.md` → "Optional: enable webhook server"](./github-org-runner/README.md)
章節,這裡不重複貼。Webhook 啟用後可以把 `org-runner.yaml` 的 `minReplicas` 改回 `0`,
走真正的 scale-to-zero 省資源。
