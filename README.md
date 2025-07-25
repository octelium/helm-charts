# Octelium Helm Charts


A minimal `helm install` command should look like:

```bash
helm install my-octelium-chart oci://ghcr.io/octelium/helm-charts/octelium --set octelium.domain=<DOMAIN> --set octelium.authToken=<AUTHENTICATION_TOKEN>
```

## Serving _Services_


You can serve one or more _Services_ from your remote Kubernetes cluster via the `--set octelium.serve` flag. Here is an example:


```bash
helm install my-octelium-chart oci://ghcr.io/octelium/helm-charts/octelium --set octelium.domain=<DOMAIN> --set octelium.authToken=<AUTHENTICATION_TOKEN> --set "octelium.serve={svc1}"
```

You can also serve multiple _Services_ as follows:

```bash
helm install my-octelium-chart oci://ghcr.io/octelium/helm-charts/octelium --set octelium.domain=<DOMAIN> --set octelium.authToken=<AUTHENTICATION_TOKEN> --set "octelium.serve={svc1,svc2,svc3}"
```