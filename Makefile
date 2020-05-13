.PHONY: all
all:
	docker build --build-arg TAG=$(TAG) -t ranchertest/image-build-base:$(TAG) .

.PHONY: image-push
image-push:
	docker push ranchertest/image-build-base:$(TAG)

.PHONY: image-scan
image-scan:
	trivy --severity $(SEVERITIES) --no-progress --skip-update --ignore-unfixed ranchertest/image-build-base:$(TAG)

.PHONY: image-manifest
image-manifest:
	DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create ranchertest/image-build-base:$(TAG) \
		$(shell docker image inspect ranchertest/image-build-base:$(TAG) | jq -r '.[] | .RepoDigests[0]')
