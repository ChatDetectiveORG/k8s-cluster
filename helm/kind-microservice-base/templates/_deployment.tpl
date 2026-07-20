{{- define "kind-microservice-base.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "kind-microservice-base.fullname" . }}
  labels:
    {{- include "kind-microservice-base.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  {{- with .Values.strategy }}
  strategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
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
      {{- with .Values.terminationGracePeriodSeconds }}
      terminationGracePeriodSeconds: {{ . }}
      {{- end }}
      {{- with .Values.image.pullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
      - name: {{ .Chart.Name }}
        image: {{ include "kind-microservice-base.image" . }}
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        {{- with .Values.securityContext }}
        securityContext:
          {{- toYaml . | nindent 10 }}
        {{- end }}
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
          {{- $runtimeSecret := (get $runtimeEnv "secret" | default dict) }}
          {{- if (get $runtimeSecret "enabled" | default true) }}
          - secretRef:
              name: {{ default (printf "%s-runtime-secret" .Release.Name) (get $runtimeSecret "name") }}
          {{- end }}
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
        {{- $persistence := (.Values.persistence | default dict) }}
        {{- if or (get $persistence "enabled" | default false) .Values.extraVolumeMounts }}
        volumeMounts:
          {{- if (get $persistence "enabled" | default false) }}
          - name: {{ (get $persistence "volumeName" | default "data") | quote }}
            mountPath: {{ required "persistence.mountPath is required when persistence.enabled=true" (get $persistence "mountPath") | quote }}
          {{- end }}
          {{- with .Values.extraVolumeMounts }}
          {{- toYaml . | nindent 10 }}
          {{- end }}
        {{- end }}
      {{- $podPersistence := (.Values.persistence | default dict) }}
      {{- if or (get $podPersistence "enabled" | default false) .Values.extraVolumes }}
      volumes:
        {{- if (get $podPersistence "enabled" | default false) }}
        - name: {{ (get $podPersistence "volumeName" | default "data") | quote }}
          persistentVolumeClaim:
            claimName: {{ (get $podPersistence "existingClaim" | default (include "kind-microservice-base.fullname" .)) | quote }}
        {{- end }}
        {{- with .Values.extraVolumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
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
