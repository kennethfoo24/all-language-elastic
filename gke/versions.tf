terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30, < 7.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
  }
}

# The google provider authenticates via Application Default Credentials (ADC),
# i.e. `gcloud auth application-default login`. cluster.sh handles that for you.
provider "google" {
  project = var.project_id
  region  = var.region
}
