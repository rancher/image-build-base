ARG GOLANG_VERSION=1.22.4

FROM --platform=$TARGETPLATFORM library/golang:${GOLANG_VERSION}-alpine AS golang

FROM alpine:3.23 as trivy-amd64
ARG TRIVY_VERSION=0.69.3
RUN set -ex; \
    TRIVY_TARBALL="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"; \
    TRIVY_SHA256="1816b632dfe529869c740c0913e36bd1629cb7688bd5634f4a858c1d57c88b75"; \
    wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${TRIVY_TARBALL}"; \
    echo "${TRIVY_SHA256}  ${TRIVY_TARBALL}" | sha256sum -c -; \
    tar -xzf "${TRIVY_TARBALL}"; \
    mv trivy /usr/local/bin

FROM alpine:3.23 as trivy-arm64
ARG TRIVY_VERSION=0.69.3
RUN set -ex; \
    TRIVY_TARBALL="trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"; \
    TRIVY_SHA256="7e3924a974e912e57b4a99f65ece7931f8079584dae12eb7845024f97087bdfd"; \
    wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${TRIVY_TARBALL}"; \
    echo "${TRIVY_SHA256}  ${TRIVY_TARBALL}" | sha256sum -c -; \
    tar -xzf "${TRIVY_TARBALL}"; \
    mv trivy /usr/local/bin

FROM trivy-${TARGETARCH} as trivy-base

FROM alpine:3.23
ENV GOTOOLCHAIN=local
ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH
COPY --from=golang /usr/local/go/ /usr/local/go/
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 1777 "$GOPATH"
WORKDIR $GOPATH
RUN apk --no-cache add \
    bash \
    coreutils \
    curl \
    docker \
    file \
    g++ \
    gcc \
    git \
    make \
    mercurial \
    rsync \
    subversion \
    wget \
    yq \
    zstd
COPY scripts/ /usr/local/go/bin/
COPY --from=trivy-base /usr/local/bin/ /usr/bin/
RUN set -x && \
    chmod -v +x /usr/local/go/bin/go-*.sh && \
    go version && \
    trivy image --download-db-only --quiet
