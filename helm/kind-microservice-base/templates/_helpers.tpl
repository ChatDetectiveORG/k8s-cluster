{{- define "kind-microservice-base.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else}}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "kind-microservice-base.image" -}}
{{- $registry := .Values.image.registry }}
{{- $repository := .Values.image.repository }}
{{- $tag := .Values.image.tag | toString }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{- define "kind-microservice-base.labels" -}}
app.kubernetes.io/name: {{ include "kind-microservice-base.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "kind-microservice-base.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kind-microservice-base.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "kind-microservice-base.livenessProbe" -}}
{{- if .enabled }}
{{- if .httpGet }}
httpGet:
  path: {{ .httpGet.path }}
  port: {{ .httpGet.port }}
  {{- if .httpGet.scheme }}
  scheme: {{ .httpGet.scheme }}
  {{- end }}
{{- else if .tcpSocket }}
tcpSocket:
  port: {{ .tcpSocket.port }}
{{- else if .exec }}
exec:
  command:
  {{- toYaml .exec.command | nindent 2 }}
{{- end }}
{{- if .initialDelaySeconds }}
initialDelaySeconds: {{ .initialDelaySeconds }}
{{- end }}
{{- if .periodSeconds }}
periodSeconds: {{ .periodSeconds }}
{{- end }}
{{- if .timeoutSeconds }}
timeoutSeconds: {{ .timeoutSeconds }}
{{- end }}
{{- if .successThreshold }}
successThreshold: {{ .successThreshold }}
{{- end }}
{{- if .failureThreshold }}
failureThreshold: {{ .failureThreshold }}
{{- end }}
{{- end }}
{{- end }}

{{- define "kind-microservice-base.readinessProbe" -}}
{{- if .enabled }}
{{- if .httpGet }}
httpGet:
  path: {{ .httpGet.path }}
  port: {{ .httpGet.port }}
  {{- if .httpGet.scheme }}
  scheme: {{ .httpGet.scheme }}
  {{- end }}
{{- else if .tcpSocket }}
tcpSocket:
  port: {{ .tcpSocket.port }}
{{- else if .exec }}
exec:
  command:
  {{- toYaml .exec.command | nindent 2 }}
{{- end }}
{{- if .initialDelaySeconds }}
initialDelaySeconds: {{ .initialDelaySeconds }}
{{- end }}
{{- if .periodSeconds }}
periodSeconds: {{ .periodSeconds }}
{{- end }}
{{- if .timeoutSeconds }}
timeoutSeconds: {{ .timeoutSeconds }}
{{- end }}
{{- if .successThreshold }}
successThreshold: {{ .successThreshold }}
{{- end }}
{{- if .failureThreshold }}
failureThreshold: {{ .failureThreshold }}
{{- end }}
{{- end }}
{{- end }}