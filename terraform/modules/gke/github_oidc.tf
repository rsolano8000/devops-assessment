# Optional: Configure GitHub OIDC for GitHub Actions -> GCP (no long-lived keys)
variable "github_org"  { type = string }
variable "github_repo" { type = string }

data "google_project" "current" {}

resource "google_iam_workload_identity_pool" "github" {
  provider                  = github
  workload_identity_pool_id = "gh-pool"
  display_name              = "GitHub Actions Pool"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  provider                           = github
  workload_identity_pool_id          = gh-pool
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Provider"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.repository"  = "assertion.repository"
    "attribute.actor"       = "assertion.actor"
    "attribute.ref"         = "assertion.ref"
  }
}

resource "google_service_account" "ci" {
  account_id   = "github-actions-deployer"
  display_name = "GitHub Actions Deployer"
}

# Allow repository to impersonate the SA via WIF
resource "google_service_account_iam_binding" "ci_wif" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
  ]
}

# Minimal roles for CI (adjust per least-privilege needs)
resource "google_project_iam_member" "ci_container_admin" {
  project = data.google_project.current.project_id
  role    = "roles/container.admin"
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
