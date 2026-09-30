{{- define "nexus-iq-server-ha.trimSpaceAndForwardSlashes" -}}
{{ . | trim | trimPrefix "/" | trimSuffix "/" }}
{{- end -}}

{{- define "nexus-iq-server-ha.iqServerImage" -}}
{{- if (.Values.iq_server).imageRegistry }}{{ (.Values.iq_server).imageRegistry }}/{{ (.Values.iq_server).image }}:{{ (.Values.iq_server).tag }}{{- else }}{{ (.Values.iq_server).image }}:{{ (.Values.iq_server).tag }}{{- end }}
{{- end -}}

{{- define "nexus-iq-server-ha.busyboxImage" -}}
{{- if ((.Values.global).busybox).imageRegistry }}{{ ((.Values.global).busybox).imageRegistry }}/{{ ((.Values.global).busybox).image }}:{{ ((.Values.global).busybox).tag }}{{- else }}{{ ((.Values.global).busybox).image }}:{{ ((.Values.global).busybox).tag }}{{- end }}
{{- end -}}

{{- define "nexus-iq-server-ha.imagePullSecrets" -}}
imagePullSecrets:
  - name: {{ .Values.iq_server.imagePullSecret }}
{{- end -}}

{{- define "nexus-iq-server-ha.storageClassName" -}}
{{- if .Values.iq_server.persistence.storageClassName -}}
{{ .Values.iq_server.persistence.storageClassName }}
{{- else if .Values.iq_server.persistence.storageClass.create -}}
{{ .Values.iq_server.persistence.storageClass.name | default (printf "%s-storageclass" .Release.Name) }}
{{- end -}}
{{- end -}}

{{- define "nexus-iq-server-ha.extraVolumes" -}}
{{- range . }}
- name: {{ .name }}
  {{- if .existingClaim }}
  persistentVolumeClaim:
    claimName: {{ .existingClaim }}
  {{- else if .hostPath }}
  hostPath:
    {{- toYaml .hostPath | nindent 4 }}
  {{- else if .configMap }}
  configMap:
    {{- toYaml .configMap | nindent 4 }}
  {{- else if .secret }}
  secret:
    secretName: {{ .secret }}
  {{- else if .emptyDir }}
  emptyDir:
    {{- toYaml .emptyDir | nindent 4 }}
  {{- else if .csi }}
  csi:
    {{- toYaml .csi | nindent 4 }}
  {{- else }}
  emptyDir: {}
  {{- end }}
{{- end }}
{{- end -}}

{{- define "nexus-iq-server-ha.extraVolumeMounts" -}}
{{- range . }}
- name: {{ .name }}
  mountPath: {{ .mountPath }}
  {{- if .subPath }}
  subPath: {{ .subPath }}
  {{- end }}
  {{- if hasKey . "readOnly" }}
  readOnly: {{ .readOnly }}
  {{- end }}
{{- end }}
{{- end -}}
