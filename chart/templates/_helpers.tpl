{{- define "nexus-iq-server-ha.trimSpaceAndForwardSlashes" -}}
{{ . | trim | trimPrefix "/" | trimSuffix "/" }}
{{- end -}}

{{- define "nexus-iq-server-ha.iqServerImage" -}}
{{- if (.Values.iq_server).imageRegistry }}{{ (.Values.iq_server).imageRegistry }}/{{ (.Values.iq_server).image }}:{{ (.Values.iq_server).tag }}{{- else }}{{ (.Values.iq_server).image }}:{{ (.Values.iq_server).tag }}{{- end }}
{{- end -}}

{{- define "nexus-iq-server-ha.busyboxImage" -}}
{{- if ((.Values.global).busybox).imageRegistry }}{{ ((.Values.global).busybox).imageRegistry }}/{{ ((.Values.global).busybox).image }}:{{ ((.Values.global).busybox).tag }}{{- else }}{{ ((.Values.global).busybox).image }}:{{ ((.Values.global).busybox).tag }}{{- end }}
{{- end -}}

{{- define "nexus-iq-server-ha.storageClassName" -}}
{{- if .Values.iq_server.persistence.storageClassName -}}
{{ .Values.iq_server.persistence.storageClassName }}
{{- else if .Values.iq_server.persistence.storageClass.create -}}
{{ .Values.iq_server.persistence.storageClass.name | default (printf "%s-storageclass" .Release.Name) }}
{{- end -}}
{{- end -}}
