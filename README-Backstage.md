# BackStage

## Deployment of BackStage in Docker

<https://backstage.io/docs/getting-started/>

```bash
docker pull node:24-bookworm-slim
mkdir backstage-app -p

docker run --rm -p 3000:3000 -ti -v //d/development/MasterBackstageIdp/backstage-app://app -w //app node:24-bookworm-slim bash
    pwd
    npx @backstage/create-app@latest
        Ok to proceed? (y) y
    ls
    cd backstage
 
    apt update && apt install -y curl
    apt install -y nano
    nano app-config.yaml
        listen:
          host: 0.0.0.0 
    
    yarn start
        ...      
        Rspack compiled successfully
            You can now view backstage in the browser.
        
            Local: http://localhost:3000
   
    exit
```

## Setup Authentication BackStage - GitHub 

### References
<https://backstage.io/docs/getting-started/config/authentication>
<https://backstage.io/docs/auth/>
<https://backstage.io/docs/auth/github/provider>

Github => Settings => Developer Settings => OAuth Apps => New OAuth App
    Application name: BackStage
    Homepage URL: http://localhost:3000
    Authorization callback URL: http://localhost:7007/api/auth/github/handler/frame
=> Register application (.env file)
    Client ID: *******
    Client Secret: ********    
=> Update application

### Update BackStage configuration

```bash
docker run --rm -p 3000:3000 -ti -p 7007:7007 -v //d/development/MasterBackstageIdp/backstage-app://app -w //app node:24-bookworm-slim bash

    cd backstage
 
    apt update && apt install -y nano
    nano app-config.yaml
    app:
      title: Scaffolded Backstage App
      baseUrl: http://localhost:3000
      #listen:
      #  host: 0.0.0.0

    nano app-config.local.yaml
    # Paste the following content into app-config.local.yaml, replacing the clientId and clientSecret values with the ones from your GitHub OAuth App

    exit
```

```yaml
app:
  listen:
    host: 0.0.0.0
auth:
  environment: development
  providers:
    github:
      development:
        clientId: ${AUTH_GITHUB_CLIENT_ID}
        clientSecret: ${AUTH_GITHUB_CLIENT_SECRET}
        ## uncomment if using GitHub Enterprise
        # enterpriseInstanceUrl: ${AUTH_GITHUB_ENTERPRISE_INSTANCE_URL}
        ## uncomment to set lifespan of user session
        # sessionDuration: { hours: 24 } # supports `ms` library format (e.g. '24h', '2 days'), ISO duration, "human duration" as used in code
        signIn:
          resolvers:
            # See https://backstage.io/docs/auth/github/provider#resolvers for more resolvers
            - resolver: usernameMatchingUserEntityName
```

```bash
source .env
echo $AUTH_GITHUB_CLIENT_ID
echo $AUTH_GITHUB_CLIENT_SECRET

docker run --rm -e AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID -e AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET -p 3000:3000 -ti -p 7007:7007 -v //d/development/MasterBackstageIdp/backstage-app://app -w //app node:24-bookworm-slim bash
    echo $AUTH_GITHUB_CLIENT_ID
    echo $AUTH_GITHUB_CLIENT_SECRET
```

### Backstage Backend Installation - Continued

```bash
    cd backstage
    apt-get update && apt-get install -y python3 make g++
    yarn --cwd packages/backend add --dev jest && \
    yarn install

    yarn --cwd packages/backend add @backstage/plugin-auth-backend-module-github-provider

    apt-get install -y nano

    nano packages/backend/src/index.ts
        backend.add(import('@backstage/plugin-auth-backend'));
        backend.add(import('@backstage/plugin-auth-backend-module-github-provider'));

    yarn start
```

### Backstage Frontend - Continued

```bash
nano packages/app/src/App.tsx
```

**使用多個提供者** - packages/app/src/App.tsx

```tsx
import { createApp } from '@backstage/frontend-defaults';
import catalogPlugin from '@backstage/plugin-catalog/alpha';
import { navModule } from './modules/nav';

import { githubAuthApiRef } from '@backstage/core-plugin-api';
import { SignInPageBlueprint } from '@backstage/plugin-app-react';
import { SignInPage } from '@backstage/core-components';
import { createFrontendModule } from '@backstage/frontend-plugin-api';

const signInPage = SignInPageBlueprint.make({
  params: {
    loader: async () => props =>
      (
        <SignInPage
          {...props}
          providers={[
            'guest',
            {
              id: 'github-auth-provider',
              title: 'GitHub',
              message: 'Sign in using GitHub',
              apiRef: githubAuthApiRef,
            },
          ]}
        />
      ),
  },
});

export default createApp({
  features: [
    catalogPlugin,
    navModule,
    createFrontendModule({
      pluginId: 'app',
      extensions: [signInPage],
    }),
  ],
});
```

### Backstage Resolvers - Continued

<https://backstage.io/docs/auth/github/provider#configuration>
<D:\development\MasterBackstageIdp\backstage\packages\catalog-model\examples\acme\team-a-group.yaml>

```bash
mkdir catalog/entities -p
nano catalog/entities/users.yaml
echo $PWD/catalog/entities/users.yaml

nano app-config.local.yaml
```

```yaml users.yaml
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: christseng89
spec:
  profile:
    displayName: Christ Tseng
    email: samfire5200@gmail.com
    picture: https://api.dicebear.com/7.x/avataaars/svg?seed=Leo&backgroundColor=transparent
  memberOf: [team-a]
```

```yaml app-config.local.yaml 
catalog:
  rules:
    - allow: [User, Component, System, API, Resource, Location]
  locations:
    # Local example data, file locations are relative to the backend process, typically `packages/backend`
    - type: file
      target: /app/backstage/catalog/entities/users.yaml
      # echo $PWD/catalog/entities/users.yaml
```

### Backstage Test Authentication - Continued

```bash
    yarn start
```
