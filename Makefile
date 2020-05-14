.PHONY: all
all:
	docker build --build-arg TAG=$(TAG) -t ranchertest/build-base:$(TAG) .

.PHONY: image-push
image-push:
	docker push ranchertest/build-base:$(TAG)

.PHONY: image-manifest
image-manifest:
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create ranchertest/build-base:$(TAG) \
		$(shell docker image inspect ranchertest/build-base:$(TAG) | jq -r '.[] | .RepoDigests[0]')
