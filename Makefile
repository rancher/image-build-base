UNAME_M = $(shell uname -m)
ARCH=
ifeq ($(UNAME_M), x86_64)
	ARCH=amd64
else
	ARCH=$(UNAME_M)
endif
ifeq ($(ARCH), amd64)
	DOCKERFILE = Dockerfile
else
	DOCKERFILE = Dockerfile.$(ARCH)
endif

ORG				?= rancher
TAG 			?= v1.13.15b4
GOLANG_VERSION 	?= $(shell echo $(TAG) | sed -e "s/v\(.*\)b.*/\1/g")
GOBORING_BUILD	?= $(shell echo $(TAG) | sed -e "s/v.*b//g")

.PHONY: image-build
image-build:
	docker build \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		--build-arg GOBORING_BUILD=$(GOBORING_BUILD) \
		--tag $(ORG)/hardened-build-base:$(TAG)-$(ARCH) \
		. \
		-f $(DOCKERFILE)

.PHONY: image-push
image-push:
	docker push $(ORG)/hardened-build-base:$(TAG)-$(ARCH)
