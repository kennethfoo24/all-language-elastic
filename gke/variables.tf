variable "project_id" {
  type        = string
  description = "GCP project ID to create the cluster in (required, no default)."
}

variable "region" {
  type        = string
  description = "Region for the VPC subnetwork."
  default     = "asia-southeast1"
}

variable "zone" {
  type        = string
  description = "Zone for the (zonal) GKE cluster and its node pool."
  default     = "asia-southeast1-a"
}

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster (also used as a prefix for the VPC/subnet/pool)."
  default     = "kenneth-gke"
}

variable "machine_type" {
  type        = string
  description = "Compute Engine machine type for the node pool. e2-standard-4 = 4 vCPU / 16 GB."
  default     = "e2-standard-4"
}

variable "node_count" {
  type        = number
  description = "Number of nodes in the (zonal) node pool."
  default     = 3
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size per node, in GB."
  default     = 100
}

variable "release_channel" {
  type        = string
  description = "GKE release channel: RAPID, REGULAR, or STABLE."
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, STABLE."
  }
}

# VPC-native (IP-aliasing) ranges. Defaults are private and non-overlapping; override
# only if they collide with networks you peer with.
variable "subnet_cidr" {
  type        = string
  description = "Primary CIDR for the node subnet."
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  type        = string
  description = "Secondary CIDR for Pod IPs."
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  type        = string
  description = "Secondary CIDR for Service (ClusterIP) IPs."
  default     = "10.30.0.0/20"
}

variable "additional_master_authorized_cidrs" {
  type        = list(string)
  description = "Extra CIDRs allowed to reach the Kubernetes API server, in addition to the deployer's IP auto-detected at apply time."
  default     = []
}

# ---------------------------------------------------------------------------
# Elastic org-policy labels — required on every Compute Engine instance.
# All five must be set; division/team/org must match their respective allowlists.
# ---------------------------------------------------------------------------
variable "label_division" {
  type        = string
  description = "Elastic org-policy label: 'division' (must be in the org allowlist, e.g. 'field')."
}

variable "label_team" {
  type        = string
  description = "Elastic org-policy label: 'team' (must be in the org allowlist, e.g. 'sa')."
}

variable "label_org" {
  type        = string
  description = "Elastic org-policy label: 'org' (must be in the org allowlist, e.g. 'elastic-sa')."
}

variable "label_keep_until" {
  type        = string
  description = "Elastic org-policy label: 'keep-until' date in YYYY-MM-DD format (any value accepted)."
}

variable "label_project" {
  type        = string
  description = "Elastic org-policy label: 'project' — identifies the workload (any value accepted)."
}
