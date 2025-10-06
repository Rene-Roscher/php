.PHONY: help build push test clean dev prod

# Default target
.DEFAULT_GOAL := help

# Variables
PHP_VERSION ?= 8.3
ALPINE_VERSION ?= 3.19
IMAGE_NAME ?= php
REGISTRY ?= ghcr.io/rene-roscher

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

##@ General

help: ## Display this help
	@echo "$(BLUE)Laravel PHP Docker - Universal Image$(NC)"
	@echo "Configure via ENV at runtime"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(GREEN)<target>$(NC)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

build: ## Build Docker image (PHP_VERSION=8.3)
	@echo "$(YELLOW)Building image: $(IMAGE_NAME):$(PHP_VERSION)$(NC)"
	docker build \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		-t $(IMAGE_NAME):$(PHP_VERSION) \
		-t $(IMAGE_NAME):latest \
		.
	@echo "$(GREEN)✓ Image built successfully$(NC)"

build-all: ## Build all PHP versions (8.2, 8.3, 8.4)
	@echo "$(YELLOW)Building all PHP versions...$(NC)"
	@for version in 8.2 8.3 8.4; do \
		echo "$(BLUE)Building PHP $$version$(NC)"; \
		$(MAKE) build PHP_VERSION=$$version; \
	done
	@echo "$(GREEN)✓ All versions built successfully$(NC)"

build-test: ## Build test image
	@echo "$(YELLOW)Building test image...$(NC)"
	docker build \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		-t $(IMAGE_NAME):$(PHP_VERSION)-test \
		.
	@echo "$(GREEN)✓ Test image built$(NC)"

##@ Testing

test: ## Run tests on built image
	@echo "$(YELLOW)Testing image: $(IMAGE_NAME):$(PHP_VERSION)$(NC)"
	@docker run --rm $(IMAGE_NAME):$(PHP_VERSION) php -v
	@docker run --rm $(IMAGE_NAME):$(PHP_VERSION) php -m | head -20
	@docker run --rm $(IMAGE_NAME):$(PHP_VERSION) nginx -v
	@echo "$(GREEN)✓ Basic tests passed$(NC)"

test-full: build-test ## Build and run comprehensive tests
	@echo "$(YELLOW)Running comprehensive tests...$(NC)"
	docker-compose -f docker-compose.test.yml up -d
	@sleep 10
	@echo "$(BLUE)Testing Unix Socket configuration...$(NC)"
	@curl -f http://localhost:8090/ || (echo "$(RED)✗ Test failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Comprehensive tests passed$(NC)"
	docker-compose -f docker-compose.test.yml down

test-socket-unix: ## Test Unix Socket configuration
	@echo "$(YELLOW)Testing Unix Socket...$(NC)"
	docker run -d --name test-unix -p 8090:80 \
		-e FPM_LISTEN=/run/php/php-fpm.sock \
		-v ./test-app:/var/www \
		$(IMAGE_NAME):$(PHP_VERSION)-test
	@sleep 5
	@curl -f http://localhost:8090/ && echo "$(GREEN)✓ Unix Socket OK$(NC)" || echo "$(RED)✗ Unix Socket failed$(NC)"
	@docker rm -f test-unix

test-socket-tcp: ## Test TCP Socket configuration
	@echo "$(YELLOW)Testing TCP Socket...$(NC)"
	docker run -d --name test-tcp -p 8091:80 \
		-e FPM_LISTEN=127.0.0.1:9000 \
		-v ./test-app:/var/www \
		$(IMAGE_NAME):$(PHP_VERSION)-test
	@sleep 5
	@curl -f http://localhost:8091/ && echo "$(GREEN)✓ TCP Socket OK$(NC)" || echo "$(RED)✗ TCP Socket failed$(NC)"
	@docker rm -f test-tcp

##@ Development

dev: ## Start development environment
	@echo "$(YELLOW)Starting development environment...$(NC)"
	docker-compose -f docker-compose.example.yml --profile dev up -d app-development
	@echo "$(GREEN)✓ Development running at http://localhost:8000$(NC)"

dev-logs: ## Follow development logs
	docker-compose -f docker-compose.example.yml logs -f app-development

dev-shell: ## Enter development container
	docker-compose -f docker-compose.example.yml exec app-development bash

dev-stop: ## Stop development environment
	docker-compose -f docker-compose.example.yml --profile dev down

##@ Production

prod: ## Start production environment
	@echo "$(YELLOW)Starting production environment...$(NC)"
	docker-compose -f docker-compose.example.yml up -d app-production
	@echo "$(GREEN)✓ Production running at http://localhost$(NC)"

prod-logs: ## Follow production logs
	docker-compose -f docker-compose.example.yml logs -f app-production

prod-shell: ## Enter production container
	docker-compose -f docker-compose.example.yml exec app-production bash

prod-stop: ## Stop production environment
	docker-compose -f docker-compose.example.yml down

##@ Registry

push: ## Push image to registry
	@echo "$(YELLOW)Pushing $(REGISTRY)/$(IMAGE_NAME):$(PHP_VERSION)$(NC)"
	docker tag $(IMAGE_NAME):$(PHP_VERSION) $(REGISTRY)/$(IMAGE_NAME):$(PHP_VERSION)
	docker push $(REGISTRY)/$(IMAGE_NAME):$(PHP_VERSION)
	@echo "$(GREEN)✓ Image pushed successfully$(NC)"

push-latest: ## Push latest tag (PHP 8.3)
	@echo "$(YELLOW)Pushing latest tag$(NC)"
	docker tag $(IMAGE_NAME):8.3 $(REGISTRY)/$(IMAGE_NAME):latest
	docker push $(REGISTRY)/$(IMAGE_NAME):latest
	@echo "$(GREEN)✓ Latest tag pushed$(NC)"

push-all: ## Push all PHP versions
	@for version in 8.2 8.3 8.4; do \
		echo "$(BLUE)Pushing PHP $$version$(NC)"; \
		$(MAKE) push PHP_VERSION=$$version; \
	done
	@$(MAKE) push-latest

##@ Laravel

artisan: ## Run artisan command (CMD="migrate")
	@if [ -z "$(CMD)" ]; then \
		docker-compose -f docker-compose.example.yml exec app-production php artisan; \
	else \
		docker-compose -f docker-compose.example.yml exec app-production php artisan $(CMD); \
	fi

migrate: ## Run database migrations
	docker-compose -f docker-compose.example.yml exec app-production php artisan migrate --force

optimize: ## Optimize Laravel application
	docker-compose -f docker-compose.example.yml exec app-production php artisan optimize

clear: ## Clear all Laravel caches
	docker-compose -f docker-compose.example.yml exec app-production php artisan config:clear
	docker-compose -f docker-compose.example.yml exec app-production php artisan route:clear
	docker-compose -f docker-compose.example.yml exec app-production php artisan view:clear
	docker-compose -f docker-compose.example.yml exec app-production php artisan cache:clear

##@ Monitoring

logs: ## Show all container logs
	docker-compose -f docker-compose.example.yml logs -f

health: ## Check container health
	docker-compose -f docker-compose.example.yml exec app-production /usr/local/bin/healthcheck.sh

fpm-status: ## Show PHP-FPM status
	@curl -s http://localhost/status?full 2>/dev/null || echo "Status endpoint not available"

opcache-status: ## Show OPcache status
	docker-compose -f docker-compose.example.yml exec app-production php -r "print_r(opcache_get_status());"

stats: ## Show container resource usage
	docker stats

##@ Cleanup

clean: ## Remove containers and volumes
	docker-compose -f docker-compose.example.yml down -v
	docker-compose -f docker-compose.test.yml down -v
	@echo "$(GREEN)✓ Cleaned up containers and volumes$(NC)"

clean-images: ## Remove all built images
	docker images | grep $(IMAGE_NAME) | awk '{print $$3}' | xargs -r docker rmi -f
	@echo "$(GREEN)✓ Removed all images$(NC)"

prune: ## Prune Docker system
	docker system prune -af --volumes
	@echo "$(GREEN)✓ Docker system pruned$(NC)"

##@ Utilities

shell: ## Enter container shell
	docker-compose -f docker-compose.example.yml exec app-production bash

ps: ## Show running containers
	docker-compose -f docker-compose.example.yml ps

info: ## Show image information
	@echo "$(BLUE)Image Information$(NC)"
	@docker images $(IMAGE_NAME)
	@echo ""
	@echo "$(BLUE)Container Information$(NC)"
	@docker-compose -f docker-compose.example.yml ps

version: ## Show PHP and Nginx versions
	@echo "$(BLUE)PHP Version:$(NC)"
	@docker run --rm $(IMAGE_NAME):$(PHP_VERSION) php -v
	@echo ""
	@echo "$(BLUE)Nginx Version:$(NC)"
	@docker run --rm $(IMAGE_NAME):$(PHP_VERSION) nginx -v
