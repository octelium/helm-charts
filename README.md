# Octelium Helm Charts

Helm charts for [Octelium](https://octelium.com), published as OCI artifacts to
`ghcr.io/octelium/helm-charts` and indexed on
[Artifact Hub](https://artifacthub.io/packages/search?repo=octelium).

## Charts

| Chart | Description |
| --- | --- |
| [octelium](./charts/octelium) | Runs the Octelium client in Kubernetes so it can serve in-cluster Services to your Octelium Cluster and publish remote Services inside Kubernetes. |

## Install

```bash
helm install octelium oci://ghcr.io/octelium/helm-charts/octelium \
  --namespace octelium --create-namespace \
  --set octelium.domain=<CLUSTER_DOMAIN> \
  --set octelium.auth.token=<AUTHENTICATION_TOKEN>
```

Full documentation lives in the [chart README](./charts/octelium/README.md).

## Supply chain

Every published chart is signed with [cosign](https://github.com/sigstore/cosign)
in keyless mode, so the signature is bound to this repository's publish workflow
rather than to a long lived key:

```bash
cosign verify ghcr.io/octelium/helm-charts/octelium:<CHART_VERSION> \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity https://github.com/octelium/helm-charts/.github/workflows/helm-publish.yml@refs/heads/main
```

## License

Apache-2.0. See [LICENSE](./LICENSE).
