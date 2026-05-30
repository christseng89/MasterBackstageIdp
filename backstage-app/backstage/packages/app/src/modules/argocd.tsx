import { ApiBlueprint, createFrontendModule } from '@backstage/frontend-plugin-api';
import { convertLegacyEntityContentExtension } from '@backstage/plugin-catalog-react/alpha';
import {
  ArgocdDeploymentLifecycle,
  argocdPlugin,
  isArgocdConfigured,
} from '@backstage-community/plugin-argocd';

// 1) Register the legacy plugin's API factories (argoCDApiRef =
//    apiRef{plugin.argo.cd.service}, plus the instance API) into the new frontend
//    system. convertLegacyEntityContentExtension only bridges the *component* —
//    it does NOT register the APIs that component calls via useApi(), which is why
//    DeploymentLifecycle throws "No implementation available for
//    apiRef{plugin.argo.cd.service}". We wrap each legacy ApiFactory exposed by
//    argocdPlugin.getApis() in an ApiBlueprint extension (same approach Backstage's
//    own core-compat-api uses).
const argocdApiExtensions = [...argocdPlugin.getApis()].map(factory =>
  ApiBlueprint.make({
    name: factory.api.id,
    params: defineParams => defineParams(factory),
  }),
);

// 2) Bridge the (routable) DeploymentLifecycle component as a "Deployments" tab.
const argocdLifecycleContent = convertLegacyEntityContentExtension(
  ArgocdDeploymentLifecycle,
  {
    name: 'argocd-deployment-lifecycle',
    path: 'argocd',
    title: 'Argo CD',
    filter: entity => Boolean(isArgocdConfigured(entity)),
  },
);

export const argocdModule = createFrontendModule({
  pluginId: 'catalog',
  extensions: [...argocdApiExtensions, argocdLifecycleContent],
});
