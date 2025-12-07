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
  selector:
    {{- include "kind-microservice-base.selectorLabels" . | nindent 4 }}
{{- end }}
