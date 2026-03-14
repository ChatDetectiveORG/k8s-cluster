{{- define "kind-microservice-base.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "kind-microservice-base.fullname" . }}
  labels:
    {{- include "kind-microservice-base.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
      name: http
    {{- $metrics := (.Values.metrics | default dict) }}
    {{- if (get $metrics "enabled" | default false) }}
    - port: {{ (get $metrics "servicePort" | default (get $metrics "port" | default 9090)) }}
      targetPort: {{ (get $metrics "port" | default 9090) }}
      protocol: TCP
      name: metrics
    {{- end }}
  selector:
    {{- include "kind-microservice-base.selectorLabels" . | nindent 4 }}
{{- end }}
