ARG GO_IMAGE=goboring/golang:1.13.15b4

FROM ${GO_IMAGE}
ARG TRIVY_VERSION=0.11.0
ENV LC_ALL C
ENV DEBIAN_FRONTEND noninteractive
RUN apt update                                      && \
    apt upgrade -y                                  && \
    apt install -y                                     \
        ca-certificates git bash rsync make wget curl  \
        software-properties-common apt-utils jq rpm && \ 
    apt-get --assume-yes clean

RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add && \
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian buster stable"
RUN apt update                 && \
    apt upgrade -y             && \
    apt-cache policy docker-ce && \
    apt install -y docker-ce

RUN if [ "$(go env GOARCH)" = "arm64" ]; then \
        wget https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz && \
        tar -zxvf trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz                                                && \
        mv trivy /usr/local/bin;                                                                              \
    else                                                                                                      \
        wget https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz && \
        tar -zxvf trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz                                                && \
        mv trivy /usr/local/bin;                                                                              \
    fi

RUN trivy --download-db-only
