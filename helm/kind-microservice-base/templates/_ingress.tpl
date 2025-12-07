{{- define "kind-microservice-base.ingress" -}}
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "kind-microservice-base.fullname" . }}
  labels:
    {{- include "kind-microservice-base.labels" . | nindent 4 }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: {{ .Values.ingress.path }}
            pathType: {{ .Values.ingress.pathType }}
            backend:
              service:
                name: {{ include "kind-microservice-base.fullname" . }}
                port:
                  number: {{ .Values.service.port }}
{{- end }}
{{- end }}

