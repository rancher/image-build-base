UNAME_M = $(shell uname -m)
ARCH=
ifeq ($(UNAME_M), x86_64)
	ARCH=amd64
else ($(UNAME_M), aarch64)
	ARCH=arm64
endif

ORG        ?= rancher
TAG        ?= v1.19.0
GO_VERSION ?= $(shell echo $(TAG) | sed -e "s/v\(.*\)b.*/\1/g")

.PHONY: image-build
image-build:
	docker build \
		--build-arg GOLANG_VERSION=$(GO_VERSION) \
		--tag $(ORG)/hardened-build-base:$(TAG) \
		--tag $(ORG)/hardened-build-base:$(TAG)-$(ARCH) \
		. \
		-f Dockerfile.$(ARCH)

.PHONY: image-push
image-push:
	docker push $(ORG)/hardened-build-base:$(TAG)-$(ARCH)

.PHONY: image-manifest
image-manifest:
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create --amend \
		$(ORG)/hardened-build-base:$(TAG) \
		$(ORG)/hardened-build-base:$(TAG)-$(ARCH)
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push \
		$(ORG)/hardened-build-base:$(TAG)
