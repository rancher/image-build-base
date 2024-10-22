ARG GOLANG_VERSION=1.22.4

FROM --platform=$TARGETPLATFORM library/golang:${GOLANG_VERSION}-alpine AS golang

FROM alpine:3.18 as trivy-amd64
ARG TRIVY_VERSION=0.56.2
RUN set -ex; \
    wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"; \
    tar -xzf trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz; \
    mv trivy /usr/local/bin

FROM alpine:3.18 as trivy-arm64
ARG TRIVY_VERSION=0.56.2
RUN set -ex; \
    wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"; \
    tar -xzf trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz; \
    mv trivy /usr/local/bin

FROM trivy-${TARGETARCH} as trivy-base

FROM alpine:3.18
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
