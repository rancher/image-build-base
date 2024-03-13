ORG        ?= rancher
TAG        ?= v1.22.0b1
GOLANG_VERSION ?= $(shell echo $(TAG) | sed -e "s/v\(.*\)b.*/\1/g")


.PHONY: log
log:
	@echo "TAG=$(TAG)"
	@echo "ORG=$(ORG)"
	@echo "GOLANG_VERSION=$(GOLANG_VERSION)"


