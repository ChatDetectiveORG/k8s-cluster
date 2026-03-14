{{- define "kind-microservice-base.hpa" -}}
{{- $hpa := .Values.hpa | default dict }}
{{- if (get $hpa "enabled" | default false) }}
{{- $external := (get $hpa "external" | default dict) }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "kind-microservice-base.fullname" . }}
  labels:
    {{- include "kind-microservice-base.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "kind-microservice-base.fullname" . }}
  minReplicas: {{ (get $hpa "minReplicas" | default 1) }}
  maxReplicas: {{ (get $hpa "maxReplicas" | default 5) }}
  metrics:
    {{- if (get $external "enabled" | default false) }}
    - type: External
      external:
        metric:
          name: {{ (get $external "metricName" | default "chatdetective_queue_updates_backlog") | quote }}
        target:
          type: Value
          value: {{ (get $external "targetValue" | default "200") | quote }}
    {{- else }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ (get $hpa "targetCPUUtilizationPercentage" | default 70) }}
    {{- end }}
{{- end }}
{{- end }}
