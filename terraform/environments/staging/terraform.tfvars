# Required
project_id             = "directed-craft-469416-u3"
region                 = "us-central1"
location               = "us-central1-a" # keep regional; switch to a zone (e.g., us-central1-a) for a zonal cluster
name                   = "gkestaging"
env                    = "staging"
artifact_repo          = "app-images-staging"
master_ipv4_cidr_block = "172.30.0.16/28"


# Safe defaults to avoid SSD quota limits
node_count   = 1             # regional => 3 nodes total
disk_type    = "pd-standard" # avoids SSD_TOTAL_GB quota
disk_size_gb = 50            # smaller boot disks

# Optional overrides
# machine_type = "e2-standard-2"
# network      = "default"
# subnetwork   = "default"
# artifact_repo = "app-images"