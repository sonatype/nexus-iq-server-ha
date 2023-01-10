{{- define "trimSpaceAndForwardSlashes" -}}
{{ . | trim | trimPrefix "/" | trimSuffix "/" }}
{{- end -}}
