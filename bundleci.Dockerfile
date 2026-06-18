FROM scratch

LABEL operators.operatorframework.io.bundle.mediatype.v1=registry+v1
LABEL operators.operatorframework.io.bundle.manifests.v1=manifests/
LABEL operators.operatorframework.io.bundle.metadata.v1=metadata/
LABEL operators.operatorframework.io.bundle.package.v1=ptp-operator
LABEL operators.operatorframework.io.bundle.channels.v1=alpha
LABEL operators.operatorframework.io.metrics.builder=operator-sdk-v1.36.1+git
LABEL operators.operatorframework.io.metrics.mediatype.v1=metrics+v1
LABEL operators.operatorframework.io.metrics.project_layout=go.kubebuilder.io/v3

LABEL operators.operatorframework.io.test.mediatype.v1=scorecard+v1
LABEL operators.operatorframework.io.test.config.v1=tests/scorecard/

LABEL name="ptp/ptp-operator-bundle-mono-operator-bundle"
LABEL summary="PTP Operator Bundle Mono"
LABEL description="Operator bundle metadata for the PTP Operator on OpenShift."
LABEL io.k8s.display-name="PTP Operator Bundle Mono"
LABEL io.k8s.description="Operator bundle metadata for the PTP Operator on OpenShift."
LABEL io.openshift.tags="openshift,ptp,operator,bundle"
LABEL maintainer="PTP Dev Team <ptp-dev@redhat.com>"
LABEL com.redhat.component="ptp-operator-bundle-mono-operator-bundle-container"
LABEL version="4.22"
LABEL release="1"
LABEL vendor="Red Hat, Inc."
LABEL url="https://github.com/openshift/ptp-operator"
LABEL distribution-scope="public"
LABEL cpe="cpe:/a:redhat:openshift:4.22::el9"

COPY manifests/stable/*.yaml /manifests/
COPY bundle/metadata /metadata/
COPY bundle/tests/scorecard /tests/scorecard/
