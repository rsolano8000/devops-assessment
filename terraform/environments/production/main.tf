terraform {
  required_version = ">= 1.6.0"
}
# Use Application Default Credentials (ADC)
# Make sure you've run: gcloud auth application-default login
provider "google" {
  project = var.project_id
  region  = var.region
}
############################################
# Enable required GCP APIs for the project
############################################
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",          # Networking, subnets, etc.
    "container.googleapis.com",        # GKE
    "artifactregistry.googleapis.com", # Artifact Registry
  ])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

############################################
# GKE module
############################################
module "gke" {
  source = "../../modules/gke"

  # Required vars
  project_id = var.project_id
  region     = var.region
  name       = var.name
  env        = var.env
  location   = var.location

  # Optional (override defaults if you want)
  machine_type  = var.machine_type
  node_count    = var.node_count
  network       = var.network
  subnetwork    = var.subnetwork
  artifact_repo = var.artifact_repo

  # Wait for APIs to be enabled first
  depends_on = [google_project_service.required_apis]
}

# Optionally create GitHub OIDC infra once (recommend doing it in a shared infra env)
# module "github_oidc" {
#   source      = "../../modules/gke"
#   github_org  = var.github_org
#   github_repo = var.github_repo
# }
