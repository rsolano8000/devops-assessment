output "gke_cluster" {
  value = {
    name     = google_container_cluster.this.name
    location = var.location
  }
}
