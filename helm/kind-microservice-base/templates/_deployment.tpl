{{- define "kind-microservice-base.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "kind-microservice-base.fullname" . }}
  labels:
    {{- include "kind-microservice-base.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "kind-microservice-base.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "kind-microservice-base.selectorLabels" . | nindent 8 }}
      {{- $metrics := (.Values.metrics | default dict) }}
      {{- if or .Values.podAnnotations (get $metrics "enabled" | default false) }}
      annotations:
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- if (get $metrics "enabled" | default false) }}
        {{- if (get $metrics "prometheusScrape" | default true) }}
        prometheus.io/scrape: "true"
        prometheus.io/path: {{ (get $metrics "path" | default "/metrics") | quote }}
        prometheus.io/port: {{ (get $metrics "port" | default 9090) | toString | quote }}
        {{- end }}
        {{- end }}
      {{- end }}
    spec:
      {{- with .Values.image.pullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
      - name: {{ .Chart.Name }}
        image: {{ include "kind-microservice-base.image" . }}
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - name: http
          containerPort: {{ .Values.service.targetPort }}
          protocol: TCP
        {{- if (get $metrics "enabled" | default false) }}
        - name: metrics
          containerPort: {{ (get $metrics "port" | default 9090) }}
          protocol: TCP
        {{- end }}
        env:
          - name: POD_NAME
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
          - name: POD_ID
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
          {{- if (get $metrics "enabled" | default false) }}
          - name: METRICS_ADDR
            value: {{ (get $metrics "addr" | default (printf ":%d" ((get $metrics "port" | default 9090) | int))) | quote }}
          {{- end }}
          {{- with .Values.env }}
          {{- toYaml . | nindent 10 }}
          {{- end }}
        {{- $runtimeEnv := (.Values.runtimeEnv | default dict) }}
        {{- if or .Values.envFrom (get $runtimeEnv "enabled" | default false) }}
        envFrom:
          {{- if (get $runtimeEnv "enabled" | default false) }}
          - configMapRef:
              name: {{ default (printf "%s-runtime-env" .Release.Name) (get $runtimeEnv "configMapName") }}
          {{- end }}
          {{- with .Values.envFrom }}
          {{- toYaml . | nindent 10 }}
          {{- end }}
        {{- end }}
        {{- $liveness := (.Values.livenessProbe | default dict) }}
        {{- if (get $liveness "enabled" | default false) }}
        livenessProbe:
          {{- include "kind-microservice-base.livenessProbe" $liveness | nindent 10 }}
        {{- end }}
        {{- $readiness := (.Values.readinessProbe | default dict) }}
        {{- if (get $readiness "enabled" | default false) }}
        readinessProbe:
          {{- include "kind-microservice-base.readinessProbe" $readiness | nindent 10 }}
        {{- end }}
        {{- with .Values.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
