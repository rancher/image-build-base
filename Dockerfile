ARG GOLANG_VERSION=1.22.4

FROM --platform=$TARGETPLATFORM library/golang:${GOLANG_VERSION}-alpine AS golang

FROM golang AS tools
WORKDIR /src/tools
COPY tools/go.mod tools/go.sum ./
RUN go mod download
COPY tools/ ./
RUN go build -o /usr/local/go/bin/go-mod-replacer ./go-mod-replacer

FROM alpine:3.24 as trivy-amd64
ARG TRIVY_VERSION=0.74.0
RUN set -ex; \
    TRIVY_TARBALL="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"; \
    TRIVY_SHA256="2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a"; \
    wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${TRIVY_TARBALL}"; \
    echo "${TRIVY_SHA256}  ${TRIVY_TARBALL}" | sha256sum -c -; \
    tar -xzf "${TRIVY_TARBALL}"; \
    mv trivy /usr/local/bin

FROM alpine:3.24 as trivy-arm64
ARG TRIVY_VERSION=0.74.0
RUN set -ex; \
    TRIVY_TARBALL="trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"; \
    TRIVY_SHA256="b94ce1976bbf3c15b514b605ee88be7c6d94a29be2302847ff01cb794d47aad5"; \
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
COPY --from=tools /usr/local/go/bin/go-mod-replacer /usr/local/go/bin/
COPY global_overrides.json /usr/local/share/go-mod-replacer/global_overrides.json
COPY --from=trivy-base /usr/local/bin/ /usr/bin/
RUN set -x && \
    chmod -v +x /usr/local/go/bin/go-*.sh && \
    go version && \
    trivy image --download-db-only --quiet
