CI_REGISTRY_IMAGE ?= registry.gitlab.com/joern_schonhoff/powerdns-api-proxy-distroless

# Read powerdns-api-proxy version from VERSION file
POWERDNS_API_PROXY_VERSION := $(shell cat VERSION)
# Validate version format (vX.Y.Z)
VALIDATE_VERSION := $(shell echo "$(POWERDNS_API_PROXY_VERSION)" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$$' && echo "valid" || echo "invalid")

ifeq ($(VALIDATE_VERSION),invalid)
$(error Invalid VERSION format: "$(POWERDNS_API_PROXY_VERSION)". Expected vX.Y.Z)
endif

.PHONY: build-prod build-debug build verify clean-images version help

help: ## Show this help message
	@echo "powerdns-api-proxy Distroless - Build Targets"
	@echo "==============================================="
	@echo "Current powerdns-api-proxy version: $(POWERDNS_API_PROXY_VERSION)"
	@echo ""
	@grep -E '^[a-zA-Z]\S+:.*' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

version: ## Display current powerdns-api-proxy version
	@echo $(POWERDNS_API_PROXY_VERSION)

build-prod: ## Build production distroless image
	docker buildx build \
		--platform linux/arm64 \
		--build-arg POWERDNS_API_PROXY_VERSION=$(POWERDNS_API_PROXY_VERSION) \
		--label org.opencontainers.image.created=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ") \
		--tag "${CI_REGISTRY_IMAGE}:$(POWERDNS_API_PROXY_VERSION)" \
		--file Dockerfile .
	@echo "Built: powerdns-api-proxy-distroless:$(POWERDNS_API_PROXY_VERSION)"

build-debug: ## Build debug image with shell
	docker buildx build \
		--platform linux/arm64 \
		--build-arg POWERDNS_API_PROXY_VERSION=$(POWERDNS_API_PROXY_VERSION) \
		--label org.opencontainers.image.created=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ") \
		--tag "${CI_REGISTRY_IMAGE}:$(POWERDNS_API_PROXY_VERSION)-debug" \
		--file Debug.Dockerfile .
	@echo "Built: powerdns-api-proxy-distroless:$(POWERDNS_API_PROXY_VERSION)-debug"

build: build-prod build-debug ## Build both production and debug images

verify: ## Verify built production image
	@echo "Verifying powerdns-api-proxy-distroless:$(POWERDNS_API_PROXY_VERSION)..."
	docker run --rm --entrypoint /usr/local/bin/python3 ${CI_REGISTRY_IMAGE}:$(POWERDNS_API_PROXY_VERSION) \
		-c "import powerdns_api_proxy, fastapi, uvicorn, pydantic_core; print('OK')"
	@echo "✓ Image verified successfully"

clean-images: ## Remove built images
	docker rmi ${CI_REGISTRY_IMAGE}:$(POWERDNS_API_PROXY_VERSION) || true
	docker rmi ${CI_REGISTRY_IMAGE}:$(POWERDNS_API_PROXY_VERSION)-debug || true
