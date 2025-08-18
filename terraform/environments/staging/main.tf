terraform {
  required_version = ">= 1.6.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "gke" {
  source                 = "../../modules/gke"
  project_id             = var.project_id
  region                 = var.region
  name                   = "gkestaging"
  env                    = "staging"
  location               = var.location
  machine_type           = var.machine_type
  node_count             = var.node_count
  artifact_repo          = var.artifact_repo
  master_ipv4_cidr_block = var.master_ipv4_cidr_block
}

# Optionally create GitHub OIDC infra once (recommend doing it in a shared infra env)
# module "github_oidc" {
#   source      = "../../modules/gke"
#   github_org  = var.github_org
#   github_repo = var.github_repo
# }
