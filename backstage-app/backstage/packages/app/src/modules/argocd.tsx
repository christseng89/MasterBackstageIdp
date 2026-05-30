import { createFrontendModule } from '@backstage/frontend-plugin-api';
import { convertLegacyEntityContentExtension } from '@backstage/plugin-catalog-react/alpha';
import {
  ArgocdDeploymentLifecycle,
  isArgocdConfigured,
} from '@backstage-community/plugin-argocd';

// Both ArgocdDeploymentSummary and ArgocdDeploymentLifecycle are *routable* legacy
// extensions (createRoutableExtension, mountPoint: rootRouteRef).
//
// - convertLegacyEntityContentExtension binds that routeRef into the app route
//   tree (routeRef: convertLegacyRouteRef(mountPoint)), so the content/tab works.
// - convertLegacyEntityCardExtension does NOT handle the mountPoint/routeRef, so a
//   routable *card* (ArgocdDeploymentSummary) can't resolve its mount point and
//   throws "Routable extension component ... was not discovered in the app element
//   tree". We therefore expose only the lifecycle as a tab — it is the full Argo CD
//   deployment view (per-env sync/health/history) and covers what the summary card
//   showed.

const argocdLifecycleContent = convertLegacyEntityContentExtension(
  ArgocdDeploymentLifecycle,
  {
    name: 'argocd-deployment-lifecycle',
    path: 'argocd',
    title: 'Deployments',
    filter: entity => Boolean(isArgocdConfigured(entity)),
  },
);

export const argocdModule = createFrontendModule({
  pluginId: 'catalog',
  extensions: [argocdLifecycleContent],
});
