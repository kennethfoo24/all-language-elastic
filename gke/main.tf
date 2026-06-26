# =============================================================================
# main.tf — GKE Standard cluster (zonal, VPC-native) for the all-language demo.
#
# Topology: a dedicated VPC + subnet (with secondary ranges for Pods/Services),
# a Standard cluster with the default node pool removed, and one managed node
# pool. Nodes are amd64 (e2-*), so the EDOT dotnet/golang arch workarounds needed
# on local arm64 kind clusters do not apply here.
# =============================================================================

# Detect the public IP of the machine running terraform apply so it can be
# added to master_authorized_networks automatically.
data "http" "deployer_ip" {
  url = "https://ipv4.icanhazip.com"
}

locals {
  deployer_cidr           = "${chomp(data.http.deployer_ip.response_body)}/32"
  master_authorized_cidrs = concat([local.deployer_cidr], var.additional_master_authorized_cidrs)
}

# Enable the APIs the cluster needs. disable_on_destroy=false so `down` doesn't
# turn these off project-wide (other workloads may rely on them).
resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Custom-mode VPC (no auto subnets) so we control the ranges.
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  depends_on              = [google_project_service.services]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  # Secondary ranges referenced by the cluster's ip_allocation_policy below.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# GKE Standard cluster (zonal). The default node pool is removed immediately and
# replaced by the managed pool below — the recommended Terraform pattern.
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.zone # a zone here => zonal cluster; a region => regional

  remove_default_node_pool = true
  initial_node_count       = 1

  # The temporary default node pool (removed immediately after cluster creation)
  # must also satisfy org-policy label requirements or instance creation fails.
  # resource_labels sets GCP resource labels on the VMs (not Kubernetes labels).
  node_config {
    resource_labels = {
      app        = "all-language"
      division   = var.label_division
      team       = var.label_team
      org        = var.label_org
      keep-until = var.label_keep_until
      project    = var.label_project
    }
  }

  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.vpc.id
  subnetwork      = google_compute_subnetwork.subnet.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = var.release_channel
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Restrict kubectl/API-server access to the deployer's IP (detected at apply
  # time) plus any extra CIDRs in var.additional_master_authorized_cidrs.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = local.master_authorized_cidrs
      content {
        cidr_block   = cidr_blocks.value
        display_name = cidr_blocks.key == 0 ? "deployer" : "extra-${cidr_blocks.key}"
      }
    }
  }

  # Let `terraform destroy` (cluster.sh down) actually delete the cluster.
  deletion_protection = false

  depends_on = [google_project_service.services]
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-pool"
  project    = var.project_id
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD" # supports eBPF (Go auto-instrumentation)

    # cloud-platform scope keeps the demo simple; tighten for production.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    resource_labels = {
      app        = "all-language"
      division   = var.label_division
      team       = var.label_team
      org        = var.label_org
      keep-until = var.label_keep_until
      project    = var.label_project
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
