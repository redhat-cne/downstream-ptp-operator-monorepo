FROM brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_9_1.25@sha256:977bd041377a1367c8b102a460ae8e63f89905f7cf9d8235484ae658c9b47646 AS builder
ENV GO111MODULE=off
ENV CGO_ENABLED=1
ENV GOEXPERIMENT=strictfipsruntime
ENV COMMON_GO_ARGS=-race
ENV GOOS=linux
ENV GOPATH=/go

WORKDIR /go/src/github.com/redhat-cne/cloud-event-proxy
COPY . .

RUN hack/build-go.sh

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest@sha256:1bc3c5c15720506a0cf48adfdf8b623dfe704377e007d7bbae8d14876392ca6a AS bin
COPY --from=builder /go/src/github.com/redhat-cne/cloud-event-proxy/build/cloud-event-proxy /
COPY --from=builder /go/src/github.com/redhat-cne/cloud-event-proxy/plugins/*.so /plugins/

COPY LICENSE /licenses/

LABEL name="ptp/cloud-event-proxy-mono-rhel9"
LABEL summary="Cloud Event Proxy Mono"
LABEL description="Publishes PTP synchronization events using the cloud-native events framework."
LABEL io.k8s.display-name="Cloud Event Proxy Mono"
LABEL io.k8s.description="Publishes PTP synchronization events using the cloud-native events framework."
LABEL io.openshift.tags="openshift,ptp,cloud-events"
LABEL maintainer="PTP Dev Team <ptp-dev@redhat.com>"
LABEL com.redhat.component="cloud-event-proxy-mono-rhel9-container"
LABEL version="4.22"
LABEL release="1"
LABEL vendor="Red Hat, Inc."
LABEL url="https://github.com/redhat-cne/cloud-event-proxy"
LABEL distribution-scope="public"
LABEL cpe="cpe:/a:redhat:openshift:4.22::el9"

USER 65532:65532

ENTRYPOINT ["./cloud-event-proxy"]
