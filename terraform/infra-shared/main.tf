terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.30"
    }
  }
}

############################
# Inputs
############################
variable "project_id" {
  type = string
}

variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_ref" {
  type    = string
  default = "refs/heads/main"
}

variable "github_environment" {
  type    = string
  default = "" # set to "production" if you want to require env=production
}

# Pool / Provider IDs to create
variable "pool_id" {
  type    = string
  default = "pool-github1"
}

variable "pool_display_name" {
  type    = string
  default = "GitHub Pool 1"
}

variable "provider_id" {
  type    = string
  default = "github"
}

variable "provider_display_name" {
  type    = string
  default = "GitHub OIDC"
}

# CI Service Account short name (must be lowercase, start with a letter)
variable "ci_sa_name" {
  type    = string
  default = "pool-github1"
}

############################
# Providers / project data
############################
provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
}

data "google_project" "current" {}

############################
# Enable required APIs (one-time)
############################
resource "google_project_service" "required" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

############################
# Workload Identity Federation (create new)
############################
resource "google_iam_workload_identity_pool" "pool" {
  provider                  = google-beta
  workload_identity_pool_id = var.pool_id
  display_name              = var.pool_display_name
  depends_on                = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "provider" {
  provider                           = google-beta
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = var.provider_display_name

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # Map useful GitHub token claims
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.ref"              = "assertion.ref"
    "attribute.actor"            = "assertion.actor"
    "attribute.workflow"         = "assertion.workflow"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.aud"              = "assertion.aud"
    "attribute.environment"      = "assertion.environment"
  }

  # Keep ternary on one line to avoid HCL parse issues
  attribute_condition = var.github_environment == "" ? "attribute.repository=='${var.github_org}/${var.github_repo}' && attribute.ref=='${var.github_ref}'" : "attribute.repository=='${var.github_org}/${var.github_repo}' && attribute.ref=='${var.github_ref}' && attribute.environment=='${var.github_environment}'"

  depends_on = [google_iam_workload_identity_pool.pool]
}

############################
# CI Service Account
############################
resource "google_service_account" "ci" {
  account_id   = var.ci_sa_name
  display_name = "CI Deployer (GitHub Actions)"
}

############################
# Allow GitHub (OIDC) to impersonate the CI SA
############################
resource "google_service_account_iam_binding" "ci_wif" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.repository/${var.github_org}/${var.github_repo}"
  ]

  depends_on = [google_iam_workload_identity_pool_provider.provider]
}

############################
# Minimal project roles for the CI SA (tighten later)
############################
resource "google_project_iam_member" "ci_container_developer" {
  project = data.google_project.current.project_id
  role    = "roles/container.developer" # prefer developer over admin
  member  = "serviceAccount:${google_service_account.ci.email}"
}

resource "google_project_iam_member" "ci_ar_writer" {
  project = data.google_project.current.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.ci.email}"
}

resource "google_project_iam_member" "ci_secret_accessor" {
  project = data.google_project.current.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.ci.email}"
}

############################
# Outputs for GitHub Secrets
############################
output "workload_identity_provider_resource" {
  description = "Use as GCP_WORKLOAD_IDENTITY_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.provider.name
  # e.g. projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/pool-github1/providers/github
}

output "ci_service_account_email" {
  description = "Use as GCP_SERVICE_ACCOUNT_EMAIL"
  value       = google_service_account.ci.email
}
