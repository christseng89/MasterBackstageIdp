# Setup Github Organization (參考用)

> **目前實際採用的路線:per-repo secrets/variables**
>
> Scaffolded repo 仍建立在個人帳號 `christseng89/<app>` 底下,每個 repo 自己
> 透過 `backstage-app/templates/python-app/template/setup.sh` 設定 4 個 secrets
> 與 3 個 variables。本文件保留 org-level 的做法作為**未來參考**,並列出真要切到
> org 模式時必須連帶修改的所有檔案。

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
