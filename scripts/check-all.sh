#!/usr/bin/env bash
# Every offline check. Nothing here talks to AWS, pushes images or changes cloud state.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
step() { printf '\n==> %s\n' "$1"; }

step "Python lint + format"
ruff check .
ruff format --check .

step "Django system checks (deploy profile) + tests"
(cd app && DJANGO_SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')" \
  DJANGO_ALLOWED_HOSTS=ledger.example.com python3 manage.py check --deploy --fail-level ERROR)
pytest -q

step "Dependency audit"
pip-audit -r requirements.txt --progress-spinner off

step "YAML lint"
yamllint .

step "ShellCheck"
shellcheck scripts/*.sh

step "Dockerfile lint"
hadolint Dockerfile

step "GitHub Actions workflow lint"
actionlint

step "Terraform fmt / validate / mocked tests"
terraform fmt -recursive -check terraform
(
  cd terraform/stack
  terraform init -backend=false -input=false >/dev/null
  terraform validate
  terraform test
)

step "Checkov"
checkov -d terraform --framework terraform --quiet --compact
checkov -f Dockerfile --framework dockerfile --quiet --compact

echo
echo "All checks passed. Optional: make smoke (needs Docker; local only)."
