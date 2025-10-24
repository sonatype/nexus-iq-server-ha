{{- define "nexus-iq-server-ha.trimSpaceAndForwardSlashes" -}}
{{ . | trim | trimPrefix "/" | trimSuffix "/" }}
{{- end -}}

{{- define "nexus-iq-server-ha.iqServerImage" -}}
{{- if (.Values.iq_server).imageRegistry }}{{ (.Values.iq_server).imageRegistry }}/{{ (.Values.iq_server).image }}:{{ (.Values.iq_server).tag }}{{- else }}{{ (.Values.iq_server).image }}:{{ (.Values.iq_server).tag }}{{- end }}
{{- end -}}

{{- define "nexus-iq-server-ha.busyboxImage" -}}
{{- if ((.Values.global).busybox).imageRegistry }}{{ ((.Values.global).busybox).imageRegistry }}/{{ ((.Values.global).busybox).image }}:{{ ((.Values.global).busybox).tag }}{{- else }}{{ ((.Values.global).busybox).image }}:{{ ((.Values.global).busybox).tag }}{{- end }}
{{- end -}}

{{- define "nexus-iq-server-ha.fluentdImage" -}}
{{- if (.Values.fluentd.image).registry }}{{ (.Values.fluentd.image).registry }}/{{ (.Values.fluentd.image).repository }}:{{ (.Values.fluentd.image).tag }}{{- else }}{{ (.Values.fluentd.image).repository }}:{{ (.Values.fluentd.image).tag }}{{- end }}
{{- end -}}
