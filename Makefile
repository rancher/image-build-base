UNAME_M = $(shell uname -m)
ARCH=
ifeq ($(UNAME_M), x86_64)
	ARCH=amd64
else
	ARCH=$(UNAME_M)
endif

TAG 			?= v1.13.15b4
GOLANG_VERSION 	?= $(shell echo $(TAG) | sed -e "s/v\(.*\)b.*/\1/g")
GOBORING_BUILD	?= $(shell echo $(TAG) | sed -e "s/v.*b//g")

.PHONY: image-build
image-build:
	docker build \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		--build-arg GOBORING_BUILD=$(GOBORING_BUILD) \
		--tag rancher/hardened-build-base:$(TAG)-$(ARCH) \
		.

.PHONY: image-push
image-push:
	docker push rancher/hardened-build-base:$(TAG)-$(ARCH)

.PHONY: image-manifest
image-manifest:
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create rancher/hardened-build-base:$(TAG) rancher/hardened-build-base:$(TAG)-$(ARCH)
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push rancher/hardened-build-base:$(TAG)
