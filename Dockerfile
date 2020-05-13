ARG GO_IMAGE=goboring/golang:1.13.8b4

FROM ${GO_IMAGE}
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

RUN wget https://github.com/aquasecurity/trivy/releases/download/v0.6.0/trivy_0.6.0_Linux-64bit.tar.gz && \
    tar -zxvf trivy_0.6.0_Linux-64bit.tar.gz                                                           && \
    mv trivy /usr/local/bin

RUN trivy --download-db-only
