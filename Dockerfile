ARG GOLANG_VERSION=1.22.4

FROM --platform=$TARGETPLATFORM library/golang:${GOLANG_VERSION}-alpine AS golang

FROM alpine:3.24 as trivy-amd64
ARG TRIVY_VERSION=0.72.0
RUN set -ex; \
    TRIVY_TARBALL="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"; \
    TRIVY_SHA256="bbb64b9695866ce4a7a8f5c9592002c5961cab378577fa3f8a040df362b9b2ea"; \
    wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${TRIVY_TARBALL}"; \
    echo "${TRIVY_SHA256}  ${TRIVY_TARBALL}" | sha256sum -c -; \
    tar -xzf "${TRIVY_TARBALL}"; \
    mv trivy /usr/local/bin

FROM alpine:3.24 as trivy-arm64
ARG TRIVY_VERSION=0.72.0
RUN set -ex; \
    TRIVY_TARBALL="trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"; \
    TRIVY_SHA256="2ca2c023109c2db6b2b77366b6717291452d4531167377d95c79547f0c8e3467"; \
    wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${TRIVY_TARBALL}"; \
    echo "${TRIVY_SHA256}  ${TRIVY_TARBALL}" | sha256sum -c -; \
    tar -xzf "${TRIVY_TARBALL}"; \
    mv trivy /usr/local/bin

FROM trivy-${TARGETARCH} as trivy-base

FROM alpine:3.24
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
