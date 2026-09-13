# Octelium

Run the [Octelium](https://octelium.com) client as a Deployment in Kubernetes.

A single release gives you a **connector**: a long lived `octelium connect` process that joins your Octelium Cluster and, depending on how you configure it, can

- **serve** in-cluster Kubernetes Services to the Octelium Cluster, so that Users and Workloads anywhere reach them through Octelium policy enforcement;
- **publish** remote Octelium Services inside the Kubernetes cluster, so that your Pods reach them over plain `ClusterIP` addresses;
- expose an **embedded SSH** (eSSH) and **SOCKS5** (eSOCKS5) server;
- act as a **DNS forwarder** for the Cluster domain.

## TL;DR

```bash
helm install octelium oci://ghcr.io/octelium/helm-charts/octelium \
  --namespace octelium --create-namespace \
  --set octelium.domain=<CLUSTER_DOMAIN> \
  --set octelium.auth.token=<AUTHENTICATION_TOKEN>
```

Helm keeps every `--set` value in the release metadata, so for anything beyond a
quick trial prefer [assertion based authentication](#assertion-based-recommended),
which stores no secret at all, or an [existing Secret](#existing-secret).

## Requirements

- Kubernetes `>= 1.23`
- Helm `>= 3.8` (OCI registry support)

## Verifying the chart

Every published chart is signed with [cosign](https://github.com/sigstore/cosign) in keyless mode from this repository's publish workflow:

```bash
cosign verify ghcr.io/octelium/helm-charts/octelium:<CHART_VERSION> \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity https://github.com/octelium/helm-charts/.github/workflows/helm-publish.yml@refs/heads/main
```

## Authentication

Exactly one of the three methods below must be configured, otherwise the chart refuses to render.

### Assertion based (recommended)

The connector authenticates with a Kubernetes ServiceAccount token against an assertion based [IdentityProvider](https://octelium.com/docs/octelium/latest/management/core/identity-providers) on your Cluster. No secret is ever stored in the Kubernetes cluster.

```bash
helm install octelium oci://ghcr.io/octelium/helm-charts/octelium \
  --set octelium.domain=<CLUSTER_DOMAIN> \
  --set octelium.auth.assertion.enabled=true \
  --set octelium.auth.assertion.audience=<AUDIENCE>
```

The token is a short lived, audience bound [projected ServiceAccount token](https://kubernetes.io/docs/concepts/storage/projected-volumes/#serviceaccounttoken) that kubelet rotates automatically. It is mounted only for the connector container; Kubernetes API credentials are never automounted.

Set `octelium.auth.assertion.identityProvider` when the Cluster has more than one IdentityProvider of that type.

Other assertion types are supported too: `azure` and `github-actions` fetch the assertion from the platform metadata endpoint, and `jwt` reads it from a file or an environment variable you provide:

```bash
  --set octelium.auth.assertion.type=jwt \
  --set octelium.auth.assertion.jwt.file=/var/run/secrets/my-token
```

### Existing Secret

```bash
helm install octelium oci://ghcr.io/octelium/helm-charts/octelium \
  --set octelium.domain=<CLUSTER_DOMAIN> \
  --set octelium.auth.existingSecret=<SECRET_NAME> \
  --set octelium.auth.existingSecretKey=data
```

### Inline Token

```bash
  --set octelium.auth.token=<AUTHENTICATION_TOKEN>
```

The chart stores it in a Secret it creates and manages, and rolls the Pods whenever that Secret changes. Note that a value passed this way also ends up in the Helm release metadata, so prefer one of the two methods above.

## Serving in-cluster Services to the Cluster

```bash
  --set "octelium.serve={svc1,svc2.ns1}"
```

Or everything assigned to the User:

```bash
  --set octelium.serveAll=true
```

## Publishing Cluster Services inside Kubernetes

`octelium.publish` maps remote Octelium Services onto ports of the connector Pod. Enable `service.enabled` to put a `ClusterIP` Service in front of them so the rest of the Kubernetes cluster can reach them by name.

```yaml
octelium:
  domain: example.com
  publish:
    - service: postgres
      port: 5432
    - service: redis.data
      port: 6379
      name: redis
    - service: coredns
      port: 5353
      protocol: UDP

service:
  enabled: true
```

Your Pods then connect to `octelium.<namespace>.svc.cluster.local:5432`, `:6379` and `:5353`.

Each entry defaults to listening on `0.0.0.0` so that other Pods can reach it. Set `address` explicitly to narrow it down; an IPv6 address is bracketed for you.

`protocol` defaults to `TCP` and **must match the type of the Octelium Service**. The client binds a UDP listener for a UDP or DNS Service, so leaving a UDP Service at the default renders a Kubernetes TCP port that no traffic can traverse. The chart cannot infer this at render time because the Service type only becomes known once the connector reaches the Cluster.

Two listeners may not claim the same protocol and port; the chart rejects the release rather than rendering a Service the API server would refuse.

## eSSH and eSOCKS5

```yaml
octelium:
  essh:
    enabled: true
    listenAddresses: ["0.0.0.0"]
  esocks5:
    enabled: true
    listenAddresses: ["0.0.0.0"]

service:
  enabled: true
```

`listenAddresses` is not optional for in-cluster access. Without it the client binds both servers to its **Octelium tunnel addresses**, which a Kubernetes Service cannot route to, so the Service would have no reachable endpoint.

Note that the embedded SOCKS5 server performs no authentication of its own: anything that can reach the port proxies through the connector's Octelium identity. Keep it on `ClusterIP` behind a NetworkPolicy, and treat an eSSH session as full access to the connector container.

## Networking privileges

By default the container runs with every capability dropped except `NET_ADMIN`, which the client needs to create its tunnel interface. Because Kubernetes does not grant ambient capabilities, `NET_ADMIN` is only effective for uid 0, so the Pod runs as root with `allowPrivilegeEscalation: false`, a read-only root filesystem and the `RuntimeDefault` seccomp profile.

To run **fully unprivileged** as a non-root user, switch the client to its userspace network stack:

```yaml
octelium:
  network:
    implementation: gvisor

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000

securityContext:
  capabilities:
    drop: ["ALL"]
    add: []
```

This mode fits the serve and publish use cases. It cannot provide tunnel connectivity to the rest of the Pod's network namespace, and it is slower than the kernel WireGuard datapath.

The `tun` implementation mode additionally needs `/dev/net/tun`, which you can pass through with `extraVolumes`/`extraVolumeMounts` on a cluster that allows `hostPath`.

## Scaling

Each replica is an independent Octelium Session and Device — the client generates a fresh device name per process — so replicas scale the serve and publish paths horizontally and a rollout is free to overlap them.

The default update strategy is therefore `RollingUpdate` with `maxUnavailable: 0` and `maxSurge: 1`, which keeps published Services reachable across an upgrade. Switch to `Recreate` when the connector binds fixed host ports that two Pods cannot hold at once, which is the case with `hostNetwork: true`.

Because the client exposes no health endpoint, a Pod is Ready as soon as it starts, before the tunnel is up. A Service can therefore route to a connector that is still connecting or reconnecting. Set `readinessProbe` yourself if you have a signal worth probing — a TCP probe against an eSSH or eSOCKS5 port is the closest available approximation.

## Values

### Chart wide

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `nameOverride` | string | `""` | Override the chart name used in resource names. |
| `fullnameOverride` | string | `""` | Override the generated resource name entirely. |
| `commonLabels` | object | `{}` | Labels added to every rendered resource. |
| `commonAnnotations` | object | `{}` | Annotations added to every rendered resource. |

### Image

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `image.repository` | string | `ghcr.io/octelium/octelium` | Client image. |
| `image.tag` | string | `""` | Defaults to the chart `appVersion`. |
| `image.digest` | string | `""` | Pin by digest. Takes precedence over `tag`. |
| `image.pullPolicy` | string | `IfNotPresent` | `Always`, `IfNotPresent` or `Never`. |
| `imagePullSecrets` | list | `[]` | Pull secrets for a private registry. |

### Octelium

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `octelium.domain` | string | `""` | Cluster domain. **Required.** |
| `octelium.auth.token` | string | `""` | Authentication Token stored in a chart managed Secret. |
| `octelium.auth.existingSecret` | string | `""` | Name of an existing Secret holding the Token. |
| `octelium.auth.existingSecretKey` | string | `data` | Key inside `existingSecret`. |
| `octelium.auth.logout` | bool | `true` | Log the Session out on shutdown. |
| `octelium.auth.scopes` | list | `[]` | Restrict the Session, e.g. `["service:svc1.ns1"]`. |
| `octelium.auth.assertion.enabled` | bool | `false` | Use assertion based authentication. |
| `octelium.auth.assertion.type` | string | `kubernetes` | `kubernetes`, `jwt`, `azure` or `github-actions`. |
| `octelium.auth.assertion.identityProvider` | string | `""` | IdentityProvider name or UID. |
| `octelium.auth.assertion.audience` | string | `""` | Assertion audience. |
| `octelium.auth.assertion.projectedToken.enabled` | bool | `true` | Use a projected ServiceAccount token instead of the automounted one. |
| `octelium.auth.assertion.projectedToken.expirationSeconds` | int | `3600` | Projected token lifetime, `600`–`86400`. |
| `octelium.auth.assertion.projectedToken.mountPath` | string | `/var/run/secrets/octelium.com/serviceaccount` | Where the token is projected. |
| `octelium.auth.assertion.jwt.file` | string | `""` | JWT file path, for the `jwt` type. |
| `octelium.auth.assertion.jwt.env` | string | `""` | JWT environment variable, for the `jwt` type. |
| `octelium.serve` | list | `[]` | Services served to the Cluster. |
| `octelium.serveAll` | bool | `false` | Serve every Service assigned to the User. |
| `octelium.publish` | list | `[]` | Remote Services published on the Pod. Entries take `service`, `port`, optional `protocol` (`TCP`/`UDP`), `address` and `name`. |
| `octelium.essh.enabled` | bool | `false` | Run the embedded SSH server. |
| `octelium.essh.user` | string | `""` | Force a host user for eSSH sessions. |
| `octelium.essh.port` | int | `22022` | eSSH port. |
| `octelium.essh.listenAddresses` | list | `[]` | eSSH listen addresses. Required for in-cluster access. |
| `octelium.essh.disableSFTP` | bool | `false` | Refuse SFTP subsystem requests. |
| `octelium.essh.allowAnyEnv` | bool | `false` | Let clients set arbitrary environment variables. |
| `octelium.esocks5.enabled` | bool | `false` | Run the embedded SOCKS5 server. |
| `octelium.esocks5.port` | int | `1080` | eSOCKS5 port. |
| `octelium.esocks5.listenAddresses` | list | `[]` | eSOCKS5 listen addresses. Required for in-cluster access. |
| `octelium.dns.disabled` | bool | `false` | Do not apply the Cluster private DNS. |
| `octelium.dns.local.enabled` | bool | `false` | Pass `--localdns`. The client always runs the local DNS server in container mode. |
| `octelium.dns.local.listenAddress` | string | `""` | Local DNS listen address, `IP` or `IP:port`. |
| `octelium.dns.full` | bool | `false` | Route every DNS query to the Cluster DNS. |
| `octelium.network.ipMode` | string | `""` | `v4`, `v6` or `both`. |
| `octelium.network.mtu` | int | `0` | Tunnel MTU, up to `1500`. |
| `octelium.network.keepAliveSeconds` | int | `0` | Tunnel keepalive. `0` uses the default of 30. |
| `octelium.network.tunnelMode` | string | `""` | `wireguard` or `quicv0` (experimental). |
| `octelium.network.implementation` | string | `""` | `kernel`, `tun` or `gvisor`. |
| `octelium.dev` | bool | `false` | Dev mode. |
| `octelium.insecureTLS` | bool | `false` | Skip TLS verification. Testing only. |
| `octelium.extraArgs` | list | `[]` | Extra `octelium connect` arguments. |
| `octelium.extraEnv` | list | `[]` | Extra environment variables. Cannot redefine `OCTELIUM_DOMAIN`, `OCTELIUM_HOME` or `OCTELIUM_AUTH_TOKEN`. |
| `octelium.extraEnvFrom` | list | `[]` | Extra `envFrom` sources. |

### Workload

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `replicaCount` | int | `1` | Replicas. Ignored when autoscaling is enabled. |
| `revisionHistoryLimit` | int | `10` | ReplicaSets retained for rollback. |
| `updateStrategy` | object | `RollingUpdate`, surge 1, unavailable 0 | Deployment update strategy. |
| `terminationGracePeriodSeconds` | int | `30` | Shutdown grace period. |
| `resources` | object | requests `50m` / `64Mi` | Container resources. |
| `livenessProbe` | object | `{}` | Liveness probe. |
| `readinessProbe` | object | `{}` | Readiness probe. |
| `startupProbe` | object | `{}` | Startup probe. |
| `lifecycle` | object | `{}` | Container lifecycle hooks. |
| `podAnnotations` | object | `{}` | Extra Pod annotations. |
| `podLabels` | object | `{}` | Extra Pod labels. |
| `rollOnSecretChange` | bool | `true` | Roll Pods when the chart managed Secret changes. |
| `podSecurityContext` | object | see `values.yaml` | Pod security context. |
| `securityContext` | object | see `values.yaml` | Container security context. |
| `emptyDirVolumes.octeliumHome` | object | `/var/lib/octelium` | Writable state directory, exported as `OCTELIUM_HOME`. |
| `emptyDirVolumes.tmp` | object | `/tmp` | Writable temporary directory. |
| `extraVolumes` | list | `[]` | Extra volumes. `octelium-home`, `tmp` and `octelium-assertion` are reserved. |
| `extraVolumeMounts` | list | `[]` | Extra volume mounts. |
| `initContainers` | list | `[]` | Extra init containers. |
| `extraContainers` | list | `[]` | Sidecar containers. |
| `hostNetwork` | bool | `false` | Share the node network namespace. |
| `dnsPolicy` | string | `""` | Pod DNS policy. |
| `dnsConfig` | object | `{}` | Pod DNS configuration. |
| `hostAliases` | list | `[]` | Extra `/etc/hosts` entries. |

### Scheduling and availability

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `nodeSelector` | object | `{}` | Node selector. |
| `tolerations` | list | `[]` | Tolerations. |
| `affinity` | object | `{}` | Affinity rules. |
| `topologySpreadConstraints` | list | `[]` | Topology spread constraints. |
| `priorityClassName` | string | `""` | PriorityClass. |
| `schedulerName` | string | `""` | Alternative scheduler. |
| `runtimeClassName` | string | `""` | RuntimeClass. |
| `autoscaling.enabled` | bool | `false` | Create a HorizontalPodAutoscaler. |
| `autoscaling.minReplicas` | int | `1` | Minimum replicas. |
| `autoscaling.maxReplicas` | int | `10` | Maximum replicas. |
| `autoscaling.targetCPUUtilizationPercentage` | int | `80` | CPU target. `0` disables. |
| `autoscaling.targetMemoryUtilizationPercentage` | int | `0` | Memory target. `0` disables. |
| `autoscaling.behavior` | object | `{}` | HPA scaling behavior. |
| `podDisruptionBudget.enabled` | bool | `false` | Create a PodDisruptionBudget. |
| `podDisruptionBudget.minAvailable` | int/string | `1` | Minimum available Pods. Used when `maxUnavailable` is empty. |
| `podDisruptionBudget.maxUnavailable` | int/string | `""` | Maximum unavailable Pods. Takes precedence over `minAvailable`. |
| `podDisruptionBudget.unhealthyPodEvictionPolicy` | string | `""` | Requires Kubernetes `>= 1.27`. |

### Service and ServiceAccount

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `service.enabled` | bool | `false` | Expose published Services, eSSH and eSOCKS5. |
| `service.type` | string | `ClusterIP` | `ClusterIP`, `NodePort` or `LoadBalancer`. |
| `service.clusterIP` | string | `""` | Explicit cluster IP. `None` for headless. |
| `service.annotations` | object | `{}` | Service annotations. |
| `service.labels` | object | `{}` | Service labels. |
| `service.loadBalancerIP` | string | `""` | LoadBalancer IP. |
| `service.loadBalancerSourceRanges` | list | `[]` | Allowed source ranges. |
| `service.externalTrafficPolicy` | string | `""` | `Cluster` or `Local`. |
| `service.sessionAffinity` | string | `""` | `ClientIP` or `None`. |
| `service.extraPorts` | list | `[]` | Additional Service ports. |
| `serviceAccount.create` | bool | `true` | Create a dedicated ServiceAccount. |
| `serviceAccount.automount` | bool | `false` | Automount Kubernetes API credentials. |
| `serviceAccount.annotations` | object | `{}` | ServiceAccount annotations. |
| `serviceAccount.labels` | object | `{}` | ServiceAccount labels. |
| `serviceAccount.name` | string | `""` | ServiceAccount name. |

## Upgrading from 0.x to 1.0.0

`1.0.0` reorganizes the `octelium.*` values. Unknown keys are rejected by `values.schema.json`, so an upgrade that still uses the old names fails fast instead of silently dropping settings.

| 0.x | 1.0.0 |
| --- | --- |
| `octelium.authToken` | `octelium.auth.token` |
| `octelium.authTokenSecret` | `octelium.auth.existingSecret` |
| `octelium.authTokenSecretKey` | `octelium.auth.existingSecretKey` |
| `octelium.assertion.enabled` | `octelium.auth.assertion.enabled` |
| `octelium.assertion.type` | `octelium.auth.assertion.type` |
| `octelium.assertion.audience` | `octelium.auth.assertion.audience` |
| `octelium.args` | `octelium.extraArgs` |
| `octelium.serve` | `octelium.serve` (unchanged) |

Other behavior changes in `1.0.0`:

- **An authentication method is now mandatory.** Previously a release with no Token and no assertion rendered a Pod that could never authenticate.
- **`serviceAccount.automount` now defaults to `false`.** Assertion based authentication uses a dedicated projected token instead of the automounted API credentials. If your Cluster IdentityProvider requires the legacy token, set `octelium.auth.assertion.projectedToken.enabled=false` together with `serviceAccount.automount=true`.
- **`octelium.assertion.audience` now takes effect for the `kubernetes` type.** In `0.x` it was silently ignored.
- **The root filesystem is read-only** and the state directory moved to the `OCTELIUM_HOME` emptyDir at `/var/lib/octelium`.
- **The update strategy is `RollingUpdate` with `maxUnavailable: 0`**, so a rollout surges before it terminates.
- **The ServiceAccount is no longer created when `serviceAccount.create=false`.** In `0.x` a truthiness bug created it anyway.
- **Default resource requests are set** (`50m` CPU, `64Mi` memory).

## License

Apache-2.0. See [LICENSE](https://github.com/octelium/helm-charts/blob/main/LICENSE).
