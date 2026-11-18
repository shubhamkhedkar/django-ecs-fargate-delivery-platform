.PHONY: venv check test lint run smoke tf-test deploy-dry-run

VENV ?= .venv
export PATH := $(CURDIR)/$(VENV)/bin:$(PATH)

venv:
	python3 -m venv $(VENV) && $(VENV)/bin/pip install -r requirements-dev.txt checkov

check:
	./scripts/check-all.sh

test:
	pytest -q

lint:
	ruff check . && ruff format --check . && yamllint . && shellcheck scripts/*.sh && hadolint Dockerfile

run:
	cd app && DJANGO_DEBUG=true python manage.py migrate && DJANGO_DEBUG=true python manage.py seed_demo \
		&& DJANGO_DEBUG=true python manage.py runserver 127.0.0.1:8000

smoke:
	./scripts/compose-smoke.sh

tf-test:
	cd terraform/stack && terraform init -backend=false -input=false >/dev/null && terraform validate && terraform test

deploy-dry-run:
	./scripts/deploy.sh
