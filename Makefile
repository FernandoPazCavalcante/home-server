PROXIED_STACKS := books media net utils
RAW_STACKS     := plex podcasts auth
STACKS         := proxy $(PROXIED_STACKS) $(RAW_STACKS)
CADDY_NETWORK  := caddy

.PHONY: help all down logs ps net-create $(STACKS) $(addsuffix -down,$(STACKS)) $(addsuffix -logs,$(STACKS))

help:
	@echo "Targets:"
	@echo "  all              Bring up every stack (creates caddy net first)"
	@echo "  down             Stop every stack"
	@echo "  ps               Show all containers"
	@echo "  logs             Tail logs of every stack"
	@echo "  net-create       Create the external 'caddy' docker network"
	@echo "  proxy            Bring up reverse proxy stack"
	@echo "  <stack>          Bring up one stack: $(STACKS)"
	@echo "                   Proxied stacks ($(PROXIED_STACKS)) auto-start proxy"
	@echo "  <stack>-down     Stop one stack"
	@echo "  <stack>-logs     Tail logs of one stack"

net-create:
	@docker network inspect $(CADDY_NETWORK) >/dev/null 2>&1 || docker network create $(CADDY_NETWORK)

all: net-create
	docker compose up -d --build

down:
	docker compose down

ps:
	docker compose ps

logs:
	docker compose logs -f --tail=100

proxy: net-create
	docker compose -f proxy-docker-compose.yaml up -d --build

proxy-down:
	docker compose -f proxy-docker-compose.yaml down

proxy-logs:
	docker compose -f proxy-docker-compose.yaml logs -f --tail=100

define proxied_stack_targets
$(1): proxy
	docker compose -f $(1)-docker-compose.yaml up -d

$(1)-down:
	docker compose -f $(1)-docker-compose.yaml down

$(1)-logs:
	docker compose -f $(1)-docker-compose.yaml logs -f --tail=100
endef

define raw_stack_targets
$(1):
	docker compose -f $(1)-docker-compose.yaml up -d

$(1)-down:
	docker compose -f $(1)-docker-compose.yaml down

$(1)-logs:
	docker compose -f $(1)-docker-compose.yaml logs -f --tail=100
endef

$(foreach s,$(PROXIED_STACKS),$(eval $(call proxied_stack_targets,$(s))))
$(foreach s,$(RAW_STACKS),$(eval $(call raw_stack_targets,$(s))))
