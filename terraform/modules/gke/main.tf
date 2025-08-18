resource "google_service_account" "gke_nodes" {
  account_id   = "${var.name}-nodes"
  display_name = "SA for ${var.name} node pool"
}

resource "google_container_cluster" "this" {
  name     = var.name
  location = var.location

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  network         = var.network
  subnetwork      = var.subnetwork

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {}

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  addons_config {
    http_load_balancing { disabled = false }
    gke_backup_agent_config { enabled = false }
  }
}

resource "google_container_node_pool" "primary" {
  name       = "${var.name}-np"
  location   = var.location
  cluster    = google_container_cluster.this.name
  node_count = var.node_count

  node_config {
    machine_type   = var.machine_type
    disk_type      = var.disk_type       
    disk_size_gb   = var.disk_size_gb    
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    metadata = {
      disable-legacy-endpoints = "true"
    }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    labels = {
      env = var.env
    }
    tags = ["gke", var.env]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Artifact Registry (Docker)
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = var.artifact_repo
  description   = "Docker repo for app images"
  format        = "DOCKER"
}

output "cluster_name" {
  value = google_container_cluster.this.name
}

output "endpoint" {
  value = google_container_cluster.this.endpoint
}

output "artifact_repository" {
  value = google_artifact_registry_repository.docker_repo.repository_id
}
