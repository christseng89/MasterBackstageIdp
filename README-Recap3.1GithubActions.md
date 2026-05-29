# Github Actions Plugins

<https://backstage.io/plugins/>
<https://github.com/backstage/community-plugins/tree/main/workspaces/github/plugins/github-actions>

## Install the GitHub Actions Plugin

```bash
# From your Backstage root directory
yarn --cwd packages/app add @backstage-community/plugin-github-actions
```

```tsx App.tsx
import githubActionsPlugin from '@backstage-community/plugin-github-actions/alpha';

// ...

export default createApp({
  features: [
    // ...
    githubActionsPlugin,
    // ...
  ],
});
```


```bash
yarn start
```
