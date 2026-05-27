# Setup Github Organization

## Create a GitHub Organization

Github → New Organization (free) → 

- Organization name: `intelligent-ltd`
- Contact email: `samfire5200@gmail.com`
- My personal account: `christseng89 (Chris Tseng)`

→ Next → Search by username, full name or email address

- christseng889 Samfire5202
- samfire5201@gmail.com (Invite by email)

-> Complete setup -> Follow

## Test gh commands

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

gh secret list --org intelligent-ltd
gh variable list --org intelligent-ltd
```

## New shell session to use Org variables and secrets

```bash
./setup-org.sh
```
