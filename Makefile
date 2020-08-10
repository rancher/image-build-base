ARCH=
ifeq ($(shell uname -m), x86_64)
	ARCH=amd64
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
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push rancher/build-base:$(TAG)-$(ARCH)
