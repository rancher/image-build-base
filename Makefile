.PHONY: all
all:
	docker build --build-arg TAG=$(TAG) -t rancher/build-base:$(TAG) .

.PHONY: image-push
image-push:
	docker push rancher/build-base:$(TAG)

.PHONY: image-manifest
image-manifest:
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create rancher/build-base:$(TAG) \
		$(shell docker image inspect rancher/build-base:$(TAG) | jq -r '.[] | .RepoDigests[0]')
