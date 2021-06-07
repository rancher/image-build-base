ARG GOLANG_VERSION=1.13.15
FROM library/golang:${GOLANG_VERSION}-alpine AS goboring
ARG GOBORING_BUILD=4
RUN apk --no-cache add \
    bash \
    g++
ADD https://go-boringcrypto.storage.googleapis.com/go${GOLANG_VERSION}b${GOBORING_BUILD}.src.tar.gz /usr/local/boring.tgz
WORKDIR /usr/local/boring
RUN tar xzf ../boring.tgz
WORKDIR /usr/local/boring/go/src
RUN ./make.bash
COPY scripts/ /usr/local/boring/go/bin/

FROM library/golang:${GOLANG_VERSION}-alpine AS trivy
ARG TRIVY_VERSION=0.11.0
RUN set -ex; \
    if [ "$(go env GOARCH)" = "arm64" ]; then \
        wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"; \
        tar -xzf trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz --include trivy -C /usr/local/bin; \
        mv trivy /usr/local/bin;                             \
    else                                                     \
        wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"; \
        tar -xzf trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz;  \
        mv trivy /usr/local/bin;                             \
    fi

FROM library/golang:${GOLANG_VERSION}-alpine
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
    rsync \
    subversion \
    wget
RUN rm -fr /usr/local/go/*
COPY --from=goboring /usr/local/boring/go/ /usr/local/go/
COPY --from=trivy /usr/local/bin/ /usr/bin/
RUN set -x \
 && chmod -v +x /usr/local/go/bin/go-*.sh \
 && go version \
 && trivy --download-db-only --quiet
