output "cluster_name" {
  description = "Name of the created GKE cluster."
  value       = google_container_cluster.primary.name
}

output "location" {
  description = "Zone (or region) the cluster runs in."
  value       = google_container_cluster.primary.location
}

output "project_id" {
  description = "Project the cluster was created in."
  value       = var.project_id
}

output "region" {
  description = "Region of the VPC subnetwork."
  value       = var.region
}

output "get_credentials_command" {
  description = "Command to point kubectl at this cluster (cluster.sh runs it for you)."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${google_container_cluster.primary.location} --project ${var.project_id}"
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "deployer_ip" {
  description = "Public IP detected at apply time — added to master_authorized_networks so kubectl works from this machine."
  value       = local.deployer_cidr
}
