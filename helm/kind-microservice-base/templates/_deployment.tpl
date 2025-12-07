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
        {{- if .Values.env }}
        env:
          {{- toYaml .Values.env | nindent 8 }}
        {{- end }}
        {{- if .Values.envFrom }}
        envFrom:
          {{- toYaml .Values.envFrom | nindent 8 }}
        {{- end }}
        {{- if .Values.livenessProbe.enabled }}
        livenessProbe:
          {{- include "kind-microservice-base.livenessProbe" .Values.livenessProbe | nindent 10 }}
        {{- end }}
        {{- if .Values.readinessProbe.enabled }}
        readinessProbe:
          {{- include "kind-microservice-base.readinessProbe" .Values.readinessProbe | nindent 10 }}
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
