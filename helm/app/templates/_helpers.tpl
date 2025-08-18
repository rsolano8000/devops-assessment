{{- define "app.name" -}}
app
{{- end -}}

{{- define "app.fullname" -}}
{{ include "app.name" . }}
{{- end -}}
