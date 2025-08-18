############################
# Required inputs
############################
variable "project_id" {
  type        = string
  description = "The GCP project ID where resources will be created."
}

variable "region" {
  type        = string
  description = "The region for deploying regional resources (e.g., us-central1)."
}

variable "name" {
  type        = string
  description = "Base name for the GKE cluster and related resources (lowercase, digits, hyphens)."
}

variable "env" {
  type        = string
  description = "Deployment environment name (e.g., dev, staging, production)."
  validation {
    condition     = can(regex("^(dev|staging|prod|production)$", var.env))
    error_message = "env must be one of: dev, staging, prod, production."
  }
}

variable "location" {
  type        = string
  description = "Cluster location: use region for regional clusters (e.g., us-central1) or zone for zonal (e.g., us-central1-a)."
}

############################
# Optional inputs (with safe defaults)
############################
variable "machine_type" {
  type        = string
  default     = "e2-standard-2"
  description = "Machine type for GKE nodes."
}

# Set to 1 to avoid regional quota blowups (regional = 3 zones × node_count).
variable "node_count" {
  type        = number
  default     = 1
  description = "Nodes per zone in the primary node pool. Regional clusters create this many in 3 zones."
  validation {
    condition     = var.node_count >= 1
    error_message = "node_count must be at least 1."
  }
}

# Use non-SSD by default to bypass SSD_TOTAL_GB quota.
variable "disk_type" {
  type        = string
  default     = "pd-standard"
  description = "Boot disk type for nodes: pd-standard | pd-balanced | pd-ssd."
  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.disk_type)
    error_message = "disk_type must be one of: pd-standard, pd-balanced, pd-ssd."
  }
}

# Smaller boot disks to lower total GB across zones.
variable "disk_size_gb" {
  type        = number
  default     = 50
  description = "Boot disk size for nodes (GB)."
  validation {
    condition     = var.disk_size_gb >= 20
    error_message = "disk_size_gb must be at least 20 GB."
  }
}

variable "network" {
  type        = string
  default     = "default"
  description = "VPC network name for the cluster."
}

variable "subnetwork" {
  type        = string
  default     = "default"
  description = "Subnetwork name within the chosen VPC."
}

variable "artifact_repo" {
  type        = string
  default     = "app-images"
  description = "Artifact Registry repository name for container images."
}
variable "master_ipv4_cidr_block" {
  type        = string
  description = "Non-overlapping /28 for the GKE control plane (private clusters)."
  # No default so each env must choose a unique /28
}
