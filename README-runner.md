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
