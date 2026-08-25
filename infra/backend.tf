# Backend remoto obligatorio (requisito del enunciado: el estado de Terraform
# NUNCA se versiona en el repositorio — ver .gitignore).
#
# El bucket se crea UNA VEZ, fuera de este módulo, para evitar el problema del
# huevo y la gallina (Terraform no puede gestionar el backend que él mismo
# necesita para arrancar). Comando de bootstrap (documentado también en
# infra/README.md):
#
#   gcloud storage buckets create gs://<PROJECT_ID>-tfstate `
#     --project=<PROJECT_ID> --location=<REGION> --uniform-bucket-level-access
#   gcloud storage buckets update gs://<PROJECT_ID>-tfstate --versioning
#
# El nombre del bucket no admite variables de Terraform (limitación del bloque
# `backend`), así que se pasa explícito aquí. Si cambias de proyecto, actualiza
# este valor y corre `terraform init -reconfigure`.
terraform {
  backend "gcs" {
    bucket = "finbank-data-platform-dev-tfstate"
    prefix = "finbank/state"
  }
}
