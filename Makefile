.PHONY: help dev-up dev-down dev-reset app-format app-credo app-test \
	app-test-unit app-test-all app-test-cover \
	python-lint shellcheck contract-validate contract-typecheck openapi-export openapi-lint openapi-breakcheck verify terraform-validate terraform-security \
	deploy deploy-plan health-report destroy

help:
	@printf '%s\n' "Targets:" \
		"" \
		"Development:" \
		"  dev-up             Start Postgres/Valkey via Docker Compose" \
		"  dev-down           Stop Compose services" \
		"  dev-reset          Stop services and wipe volumes" \
		"" \
		"Quality Checks:" \
		"  app-format         Run mix format --check-formatted" \
		"  app-credo          Run mix credo --strict" \
		"  app-test           Run mix test (requires docker compose up)" \
		"  app-test-unit      Run unit tests only (no database required)" \
		"  app-test-all       Start docker, run all tests, stop docker" \
		"  app-test-cover     Run tests with coverage report" \
		"  python-lint        Run ruff, mypy, bandit on lambdas" \
		"  shellcheck         Run ShellCheck on scripts" \
		"  contract-validate  Validate docs/API_CONTRACT.md against routes/types" \
		"  contract-typecheck Type-check frontend contract interfaces" \
		"  openapi-export     Export current OpenAPI spec to contracts/openapi.json" \
		"  openapi-lint       Lint OpenAPI spec with Spectral" \
		"  openapi-breakcheck Check for breaking changes vs origin/main" \
		"  verify             Run the default full local verification gate" \
		"  terraform-validate Validate infra and state-backend" \
		"  terraform-security Run security scans (checkov, kics)" \
		"" \
		"Deployment:" \
		"  deploy             Full deploy (build + terraform apply)" \
		"  deploy-plan        Plan only (no changes applied)" \
		"  health-report      Check deployment health status" \
		"  destroy            Tear down infrastructure"

# =============================================================================
# Development
# =============================================================================

dev-up:
	bash scripts/dev-up.sh

dev-down:
	bash scripts/dev-down.sh

dev-reset:
	bash scripts/dev-reset.sh

# =============================================================================
# Quality Checks
# =============================================================================

app-format:
	cd app && mix format --check-formatted

app-credo:
	cd app && mix credo --strict

app-test:
	cd app && mix test

# Run unit tests only (no database/redis required)
app-test-unit:
	cd app && mix test --exclude live_api \
		test/backend/stripe_test.exs \
		test/backend/checkr_test.exs \
		test/backend/google_maps_test.exs \
		test/backend/repo_auth_test.exs \
		test/backend/valkey_auth_test.exs \
		test/backend/logger_json_test.exs \
		test/backend/rds_iam_auth_test.exs \
		test/backend/elasticache_iam_auth_test.exs \
		test/backend/redis_session_store_test.exs \
		test/backend_web/error_json_test.exs \
		test/backend_web/fallback_controller_test.exs \
		test/backend_web/plugs/request_logger_test.exs \
		test/backend_web/plugs/ensure_authenticated_test.exs

# Start docker, run all tests, then stop docker
app-test-all:
	docker compose up -d --wait
	cd app && mix ecto.create --quiet || true
	cd app && mix ecto.migrate
	cd app && mix test || (docker compose down && exit 1)
	docker compose down

# Run tests with coverage report
app-test-cover:
	cd app && mix test --cover

python-lint:
	ruff check infra/lambdas
	mypy infra/lambdas
	bandit -q -r infra/lambdas

shellcheck:
	shellcheck -x -o all -S warning scripts/*.sh

contract-validate:
	bash scripts/validate-api-contract.sh

contract-typecheck:
	npm exec --yes --package typescript@latest tsc -- --noEmit -p contracts/tsconfig.json

openapi-export:
	bash scripts/export-openapi.sh

openapi-lint: openapi-export
	npm exec --yes --package @stoplight/spectral-cli -- spectral lint contracts/openapi.json --ruleset contracts/spectral.yaml

openapi-breakcheck: openapi-export
	bash scripts/check-openapi-breaking.sh

verify: app-format app-credo app-test contract-validate contract-typecheck openapi-lint

terraform-validate:
	cd infra && terraform fmt -check -recursive
	cd infra && terraform init -backend=false
	cd infra && terraform validate
	cd state-backend && terraform fmt -check -recursive
	cd state-backend && terraform init -backend=false
	cd state-backend && terraform validate

terraform-security:
	bash scripts/run-checkov.sh
	bash scripts/run-kics.sh

# =============================================================================
# Deployment
# =============================================================================

deploy:
	bash scripts/deploy.sh

deploy-plan:
	bash scripts/deploy.sh --plan-only

health-report:
	bash scripts/deployment-health-report.sh

destroy:
	bash scripts/destroy.sh
