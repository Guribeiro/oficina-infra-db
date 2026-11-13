#!/usr/bin/env bash
# Executa o Terraform do banco de um ambiente com o backend S3 correto.
#
#   scripts/tf.sh <hml|prd> <plan|apply|destroy|output>
#
# Variáveis: TF_STATE_BUCKET (obrigatória; criado pelo bootstrap/state.sh do
# oficina-infra-k8s), AWS_REGION (padrão us-east-1), AUTO_APPROVE=true (CI).
set -euo pipefail

ENVIRONMENT="${1:-}"
ACTION="${2:-plan}"

if [[ "$ENVIRONMENT" != "hml" && "$ENVIRONMENT" != "prd" ]]; then
  echo "Uso: $0 <hml|prd> <plan|apply|destroy|output>" >&2
  exit 1
fi

: "${TF_STATE_BUCKET:?Defina TF_STATE_BUCKET (bootstrap/state.sh do oficina-infra-k8s)}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export TF_VAR_environment="$ENVIRONMENT"
export TF_VAR_state_bucket="$TF_STATE_BUCKET"
export TF_IN_AUTOMATION=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/stacks/database"

APPROVE=()
[[ "${AUTO_APPROVE:-false}" == "true" ]] && APPROVE=(-auto-approve)

terraform init -input=false -reconfigure \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=oficina-infra-db/${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}"

case "$ACTION" in
  plan)    terraform plan -input=false -lock-timeout=5m -out=tfplan ;;
  apply)   terraform apply -input=false -lock-timeout=5m "${APPROVE[@]}" ;;
  destroy) terraform destroy -input=false -lock-timeout=5m "${APPROVE[@]}" ;;
  output)  terraform output ;;
  *)
    echo "Ação inválida: $ACTION" >&2
    exit 1
    ;;
esac
