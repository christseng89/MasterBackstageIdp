# Setup a Self-Hosted Runner for GitHub Actions

## Register the Self-Hosted Runner

GitHub → **Settings → Actions → Runners → New self-hosted runner**

**Download the runner package** (Git Bash on Windows):

```bash
# Create folder and enter it (relative to wherever Git Bash is opened, e.g. your home ~)
mkdir -p actions-runner && cd actions-runner

# Download the runner package
curl -L -o actions-runner-win-x64-2.334.0.zip \
  https://github.com/actions/runner/releases/download/v2.334.0/actions-runner-win-x64-2.334.0.zip

# Extract it (use PowerShell from Git Bash for unzip on Windows)
powershell -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; \
  [System.IO.Compression.ZipFile]::ExtractToDirectory('$(pwd -W)\\actions-runner-win-x64-2.334.0.zip', '$(pwd -W)')"
```

**Configure and start the runner** (replace the token with the one GitHub shows you on the *New self-hosted runner* page — it rotates):

```bash (configure only the first time; skip if already done)
./config.cmd --url https://github.com/christseng89/MasterBackstageIdp --token AC7NNQC2IOUD6UVAN5FPDV3KAXEMA
```

```bash (keep this running in the background to listen for jobs after configuration)
./run.cmd
```

## Install ArgoCD CLI on the Runner Host

The `cd` job calls `argocd login` and `argocd app sync`, so the CLI must exist on the self-hosted runner machine.

```cmd
choco install argocd-cli
argocd version
    argocd: v3.4.2+0dc6b1b
    BuildDate: 2026-05-12T21:00:01Z
    GitCommit: 0dc6b1b57dd5bb925d5b03c3d09419ab9fb4225e
    GitTreeState: clean
    GoVersion: go1.26.0
    Compiler: gc
    Platform: windows/amd64
    {"level":"fatal","msg":"Argo CD server address unspecified","time":"2026-05-14T20:24:49+08:00"}
```

(The `fatal` line is expected when `argocd version` runs without a configured server — the workflow itself handles the login.)
