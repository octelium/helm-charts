# Octelium Helm Chart

This chart runs the Octelium client in your Kubernetes cluster as a Deployment. It connects the cluster to your Octelium Cluster and can optionally serve in-cluster Kubernetes Services as Octelium Services.

## Installation

A minimal install using an authentication token:

```bash
helm install my-octelium oci://ghcr.io/octelium/helm-charts/octelium \
  --set octelium.domain=<DOMAIN> \
  --set octelium.authToken=<AUTHENTICATION_TOKEN>
```

When you pass `authToken`, the chart stores it in a Kubernetes Secret that it creates and manages.

### Using an existing Secret

To reference a token from a Secret you already manage, use `authTokenSecret`:

```bash
helm install my-octelium oci://ghcr.io/octelium/helm-charts/octelium \
  --set octelium.domain=<DOMAIN> \
  --set octelium.authTokenSecret=<K8S_SECRET_NAME>
```

The Secret key defaults to `data`. Override it with `authTokenSecretKey`:

```bash
helm install my-octelium oci://ghcr.io/octelium/helm-charts/octelium \
  --set octelium.domain=<DOMAIN> \
  --set octelium.authTokenSecret=<K8S_SECRET_NAME> \
  --set octelium.authTokenSecretKey=<KEY_NAME>
```

`authTokenSecret` takes precedence over `authToken`, so set only one.

### Secret-less authentication (assertion)

Instead of a token, the client can authenticate using your Cluster's assertion-based IdentityProvider, which avoids storing any secret in the cluster. This is used only when neither `authToken` nor `authTokenSecret` is set:

```bash
helm install my-octelium oci://ghcr.io/octelium/helm-charts/octelium \
  --set octelium.domain=<DOMAIN> \
  --set octelium.assertion.enabled=true \
  --set octelium.assertion.type=<ASSERTION_TYPE>
```

You can optionally override the audience:

```bash
  --set octelium.assertion.audience=<AUDIENCE>
```

Read more about assertion-based IdentityProviders [here](https://octelium.com/docs/octelium/latest/management/core/identity-providers).

## Serving Services

Serve one or more in-cluster Services with `octelium.serve`:

```bash
helm install my-octelium oci://ghcr.io/octelium/helm-charts/octelium \
  --set octelium.domain=<DOMAIN> \
  --set octelium.authToken=<AUTHENTICATION_TOKEN> \
  --set "octelium.serve={svc1}"
```

Multiple Services:

```bash
  --set "octelium.serve={svc1,svc2,svc3}"
```

## Extra arguments

Pass any additional `octelium connect` flags via `octelium.args`:

```bash
  --set "octelium.args={--no-dns}"
```

## Values

| Key | Default | Description |
| --- | --- | --- |
| `octelium.domain` | `""` | Octelium Cluster domain. Required. |
| `octelium.authToken` | `""` | Token value; stored in a chart-managed Secret. |
| `octelium.authTokenSecret` | `""` | Name of an existing Secret holding the token. Takes precedence over `authToken`. |
| `octelium.authTokenSecretKey` | `"data"` | Key within `authTokenSecret`. |
| `octelium.assertion.enabled` | `false` | Use assertion-based auth when no token is set. |
| `octelium.assertion.type` | `"kubernetes"` | Assertion type configured on the Cluster. |
| `octelium.assertion.audience` | `""` | Optional audience override. |
| `octelium.dev` | `false` | Enable dev mode. |
| `octelium.insecureTLS` | `false` | Disable TLS verification (testing only). |
| `octelium.serve` | `[]` | Services to serve. |
| `octelium.args` | `[]` | Extra `octelium connect` arguments. |
| `replicaCount` | `1` | Number of replicas (ignored when autoscaling is enabled). |
| `image.repository` | `ghcr.io/octelium/octelium` | Image repository. |
| `image.tag` | `""` (chart appVersion) | Image tag. |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy. |
| `resources` | `{}` | Pod resource requests/limits. |
| `autoscaling.enabled` | `false` | Enable the HorizontalPodAutoscaler. |

The standard `serviceAccount`, `nodeSelector`, `tolerations`, `affinity`, `podSecurityContext`, and `securityContext` keys are also supported.

## Networking privileges

The container is granted the `NET_ADMIN` capability so the client can set up its tunnel interface. If your nodes restrict this, the client falls back to its userspace implementation where possible.