{{- define "nexus-iq-server-ha.trimSpaceAndForwardSlashes" -}}
{{ . | trim | trimPrefix "/" | trimSuffix "/" }}
{{- end -}}

{{- define "nexus-iq-server-ha.iqServerImage" -}}
{{- if .Values.iq_server.imageRegistry }}{{ .Values.iq_server.imageRegistry }}/{{ .Values.iq_server.image }}:{{ .Values.iq_server.tag }}{{- else }}{{ .Values.iq_server.image }}:{{ .Values.iq_server.tag }}{{- end }}
{{- end -}}

{{- define "nexus-iq-server-ha.busyboxImage" -}}
{{- if .Values.busybox.imageRegistry }}{{ .Values.busybox.imageRegistry }}/{{ .Values.busybox.image }}:{{ .Values.busybox.tag }}{{- else }}{{ .Values.busybox.image }}:{{ .Values.busybox.tag }}{{- end }}
{{- end -}}
