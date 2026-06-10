#!/bin/sh
#
# Sonatype Nexus (TM) Open Source Version
# Copyright (c) 2008-present Sonatype, Inc.
# All rights reserved. Includes the third-party code listed at http://links.sonatype.com/products/nexus/oss/attributions.
#
# This program and the accompanying materials are made available under the terms of the Eclipse Public License Version 1.0,
# which accompanies this distribution and is available at http://www.eclipse.org/legal/epl-v10.html.
#
# Sonatype Nexus (TM) Professional Version is available from Sonatype, Inc. "Sonatype" and "Sonatype Nexus" are trademarks
# of Sonatype, Inc. Apache Maven is a trademark of the Apache Software Foundation. M2eclipse is a trademark of the
# Eclipse Foundation. All other trademarks are the property of their respective owners.
#

# plugin does not yet ship .prov files (https://github.com/helm-unittest/helm-unittest/issues/777)
# --verify=false is only supported in Helm 3.13+, so check version first
# Remove any existing incompatible plugin version before installing
helm plugin uninstall unittest 2>/dev/null || true

# Install helm-unittest plugin
# Note: The plugin's platformHooks field requires Helm 3.13+, so use an older
# plugin version for older Helm versions.
HELM_MAJOR=$(helm version --template '{{ .Version }}' | sed 's/v//' | cut -d. -f1)
HELM_MINOR=$(helm version --template '{{ .Version }}' | cut -d. -f2)
if [ "$HELM_MAJOR" -ge 4 ] || { [ "$HELM_MAJOR" -eq 3 ] && [ "$HELM_MINOR" -ge 13 ]; }; then
  helm plugin install https://github.com/helm-unittest/helm-unittest.git --verify=false
else
  # v0.7.2 is the last version without platformHooks (which requires Helm 3.13+)
  helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v0.7.2
fi

set -e

#update the dependencies for the chart
helm dependency update chart

# lint yaml of chart
helm lint chart

# unit test
(cd ./chart; helm unittest -t junit -o test-output.xml .)

# package the chart into tgz archives
helm package chart --destination docs
