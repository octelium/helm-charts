{{/*
Expand the name of the chart.
*/}}
{{- define "octelium.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "octelium.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "octelium.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "octelium.labels" -}}
helm.sh/chart: {{ include "octelium.chart" . }}
{{ include "octelium.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/component: connector
app.kubernetes.io/part-of: octelium
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "octelium.selectorLabels" -}}
app.kubernetes.io/name: {{ include "octelium.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "octelium.annotations" -}}
{{- with .Values.commonAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "octelium.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "octelium.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Fully qualified image reference.
*/}}
{{- define "octelium.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{/*
Name of the Secret holding the authentication Token, and the key within it.
*/}}
{{- define "octelium.authSecretName" -}}
{{- default (include "octelium.fullname" .) .Values.octelium.auth.existingSecret }}
{{- end }}

{{- define "octelium.authSecretKey" -}}
{{- if .Values.octelium.auth.existingSecret }}
{{- default "data" .Values.octelium.auth.existingSecretKey }}
{{- else }}
{{- print "data" }}
{{- end }}
{{- end }}

{{/*
Whether the chart manages its own Secret for the authentication Token.
*/}}
{{- define "octelium.createsSecret" -}}
{{- if and .Values.octelium.auth.token (not .Values.octelium.auth.existingSecret) }}
{{- print "true" }}
{{- end }}
{{- end }}

{{/*
Path of the projected ServiceAccount token used by the kubernetes assertion type.
*/}}
{{- define "octelium.projectedTokenPath" -}}
{{- printf "%s/token" (trimSuffix "/" .Values.octelium.auth.assertion.projectedToken.mountPath) }}
{{- end }}

{{/*
The argument passed to `octelium connect --assertion`.
*/}}
{{- define "octelium.assertionArg" -}}
{{- $a := .Values.octelium.auth.assertion -}}
{{- $arg := "" -}}
{{- if eq $a.type "kubernetes" -}}
  {{- if $a.projectedToken.enabled -}}
    {{- $arg = printf "jwt:file=%s" (include "octelium.projectedTokenPath" .) -}}
  {{- else -}}
    {{- $arg = "kubernetes" -}}
  {{- end -}}
{{- else if eq $a.type "jwt" -}}
  {{- if $a.jwt.file -}}
    {{- $arg = printf "jwt:file=%s" $a.jwt.file -}}
  {{- else -}}
    {{- $arg = printf "jwt:env=%s" $a.jwt.env -}}
  {{- end -}}
{{- else -}}
  {{- if $a.audience -}}
    {{- $arg = printf "%s:audience=%s" $a.type $a.audience -}}
  {{- else -}}
    {{- $arg = $a.type -}}
  {{- end -}}
{{- end -}}
{{- if $a.identityProvider -}}
{{- printf "%s:%s" $a.identityProvider $arg -}}
{{- else -}}
{{- $arg -}}
{{- end -}}
{{- end }}

{{/*
Ports exposed by the container and, when enabled, by the Kubernetes Service.
*/}}
{{- define "octelium.portList" -}}
{{- range $i, $p := .Values.octelium.publish }}
- name: {{ default (printf "publish-%v" $p.port) $p.name | trunc 15 | trimSuffix "-" }}
  port: {{ $p.port }}
  protocol: TCP
{{- end }}
{{- if .Values.octelium.essh.enabled }}
- name: essh
  port: {{ .Values.octelium.essh.port }}
  protocol: TCP
{{- end }}
{{- if .Values.octelium.esocks5.enabled }}
- name: esocks5
  port: {{ .Values.octelium.esocks5.port }}
  protocol: TCP
{{- end }}
{{- if and .Values.octelium.dns.local.enabled .Values.octelium.dns.local.listenAddress }}
- name: dns-udp
  port: {{ include "octelium.localDNSPort" . }}
  protocol: UDP
- name: dns-tcp
  port: {{ include "octelium.localDNSPort" . }}
  protocol: TCP
{{- end }}
{{- end }}

{{- define "octelium.containerPorts" -}}
{{- range $p := (include "octelium.portList" . | fromYamlArray) }}
- name: {{ $p.name }}
  containerPort: {{ $p.port }}
  protocol: {{ $p.protocol }}
{{- end }}
{{- end }}

{{- define "octelium.servicePorts" -}}
{{- range $p := (include "octelium.portList" . | fromYamlArray) }}
- name: {{ $p.name }}
  port: {{ $p.port }}
  targetPort: {{ $p.name }}
  protocol: {{ $p.protocol }}
{{- end }}
{{- end }}

{{- define "octelium.localDNSPort" -}}
{{- $addr := .Values.octelium.dns.local.listenAddress -}}
{{- if contains "]:" $addr -}}
{{- (splitList "]:" $addr) | last -}}
{{- else if and (contains ":" $addr) (not (contains "::" $addr)) -}}
{{- (splitList ":" $addr) | last -}}
{{- else -}}
{{- print "53" -}}
{{- end -}}
{{- end }}

{{/*
Reject value combinations that would deploy a Pod that cannot ever connect.
*/}}
{{- define "octelium.validateValues" -}}
{{- $o := .Values.octelium -}}
{{- if not $o.domain -}}
{{- fail "octelium.domain is required. Set it to your Octelium Cluster domain, e.g. --set octelium.domain=example.com" -}}
{{- end -}}
{{- if and $o.auth.token $o.auth.existingSecret -}}
{{- fail "octelium.auth.token and octelium.auth.existingSecret are mutually exclusive. Set only one of them" -}}
{{- end -}}
{{- if and $o.auth.assertion.enabled (or $o.auth.token $o.auth.existingSecret) -}}
{{- fail "octelium.auth.assertion.enabled cannot be combined with octelium.auth.token or octelium.auth.existingSecret. Pick a single authentication method" -}}
{{- end -}}
{{- if not (or $o.auth.token $o.auth.existingSecret $o.auth.assertion.enabled) -}}
{{- fail "No authentication method is configured. Set one of octelium.auth.token, octelium.auth.existingSecret or octelium.auth.assertion.enabled" -}}
{{- end -}}
{{- if $o.auth.assertion.enabled -}}
{{- if eq $o.auth.assertion.type "jwt" -}}
{{- if and $o.auth.assertion.jwt.file $o.auth.assertion.jwt.env -}}
{{- fail "octelium.auth.assertion.jwt.file and octelium.auth.assertion.jwt.env are mutually exclusive. Set only one of them" -}}
{{- end -}}
{{- if not (or $o.auth.assertion.jwt.file $o.auth.assertion.jwt.env) -}}
{{- fail "The jwt assertion type requires octelium.auth.assertion.jwt.file or octelium.auth.assertion.jwt.env" -}}
{{- end -}}
{{- end -}}
{{- if and (eq $o.auth.assertion.type "kubernetes") (not $o.auth.assertion.projectedToken.enabled) (not $.Values.serviceAccount.automount) -}}
{{- fail "The kubernetes assertion type with octelium.auth.assertion.projectedToken.enabled=false needs serviceAccount.automount=true so the default token is mounted" -}}
{{- end -}}
{{- end -}}
{{- if and $o.serveAll (gt (len $o.serve) 0) -}}
{{- fail "octelium.serveAll and octelium.serve are mutually exclusive. Set only one of them" -}}
{{- end -}}
{{- range $i, $p := $o.publish -}}
{{- if not $p.service -}}
{{- fail (printf "octelium.publish[%d] is missing the service field" $i) -}}
{{- end -}}
{{- if not $p.port -}}
{{- fail (printf "octelium.publish[%d] is missing the port field" $i) -}}
{{- end -}}
{{- end -}}
{{- if and $.Values.podSecurityContext.runAsNonRoot (has "NET_ADMIN" (dig "capabilities" "add" (list) $.Values.securityContext)) -}}
{{- fail "NET_ADMIN is only effective for uid 0. Either keep podSecurityContext.runAsNonRoot=false or drop NET_ADMIN and set octelium.network.implementation=gvisor" -}}
{{- end -}}
{{- end }}

{{/*
Render an emptyDir volume source, falling back to {} when nothing is set.
*/}}
{{- define "octelium.emptyDirSpec" -}}
{{- $spec := dict -}}
{{- with .medium }}{{- $_ := set $spec "medium" . }}{{- end -}}
{{- with .sizeLimit }}{{- $_ := set $spec "sizeLimit" . }}{{- end -}}
{{- toYaml $spec -}}
{{- end }}
