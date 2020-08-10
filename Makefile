UNAME_M = $(shell uname -m)
ARCH=
ifeq ($(UNAME_M), x86_64)
	ARCH=amd64
else
	ARCH=$(UNAME_M)
endif

.PHONY: all
all:
	docker build --build-arg TAG=$(TAG) -t rancher/build-base:$(TAG)-$(ARCH) .

.PHONY: image-push
image-push:
	docker push rancher/build-base:$(TAG)-$(ARCH)

.PHONY: image-manifest
image-manifest:
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create rancher/build-base:$(TAG)-$(ARCH) \
		$(shell docker image inspect rancher/build-base:$(TAG)-$(ARCH) | jq -r '.[] | .RepoDigests[0]')
