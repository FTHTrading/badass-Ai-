# ====================================================================
# PROJECT UNYKORN: DOC INTELLIGENCE INFRASTRUCTURE MANIFEST
# TARGET ECOSYSTEM: GOOGLE CLOUD PLATFORM
# DEPLOYMENT FRAMEWORK: Terraform Cloud Run Hub
# ====================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.10.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

# --------------------------------------------------------------------
# VARIABLES & METADATA
# --------------------------------------------------------------------
variable "gcp_project_id" {
  type    = string
  default = "unykorn-doc-intelligence"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "agent_nodes" {
  type = list(string)
  default = [
    "doc-intake-agent",
    "doc-kyc-kyb-agent",
    "doc-compliance-agent",
    "doc-drafter-agent",
    "doc-contract-agent",
    "doc-brokernet-agent",
    "doc-notary-agent",
    "doc-auditor-agent"
  ]
}

# --------------------------------------------------------------------
# NETWORK & FIREWALLS
# --------------------------------------------------------------------
resource "google_compute_network" "vpc_network" {
  name                    = "unykorn-doc-intel-vpc"
  auto_create_subnetworks = true
}

# --------------------------------------------------------------------
# STORAGE LAYER (THE COLD STORAGE VAULT & INDEXING DROPZONE)
# --------------------------------------------------------------------
resource "google_storage_bucket" "cold_storage_vault" {
  name                        = "evidence-locker-vault-${var.gcp_project_id}"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90 # Transition older legal documents to cold storage archive
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
}

resource "google_storage_bucket" "dropzone_bucket" {
  name                        = "doc-dropzone-vault-${var.gcp_project_id}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  cors {
    origin          = ["https://live.docs.unykorn", "https://docs.unykorn.org"]
    method          = ["POST"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}

# --------------------------------------------------------------------
# HOT STORAGE LAYER (ALLOYDB AI & VECTOR INDEXES)
# --------------------------------------------------------------------
resource "google_alloydb_cluster" "alloydb_cluster" {
  cluster_id = "unykorn-doc-intel-alloydb"
  location   = var.region
  network    = google_compute_network.vpc_network.id

  initial_user {
    password = "SuperSecureUnykornPassword2026!"
  }
}

resource "google_alloydb_instance" "alloydb_primary" {
  cluster       = google_alloydb_cluster.alloydb_cluster.name
  instance_id   = "unykorn-doc-intel-primary"
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = 4
  }

  database_flags = {
    "google_columnar_engine.enabled" = "on"
    "alloydb.enable_vector_search"   = "on"
  }
}

# --------------------------------------------------------------------
# COMPUTE LAYER (THE 8 ISOLATED CLOUD RUN AGENT SERVERS)
# --------------------------------------------------------------------

# Create IAM Service Accounts for each Node
resource "google_service_account" "agent_service_accounts" {
  for_each     = toset(var.agent_nodes)
  account_id   = "${each.value}-sa"
  display_name = "Isolated Service Account for ${each.value}"
}

# Deploy the 8 Cloud Run Instances
resource "google_cloud_run_v2_service" "agent_services" {
  for_each = toset(var.agent_nodes)
  name     = each.value
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY" # Restrict exposure; routing done via API Gateway

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.gcp_project_id}/unykorn-agent-registry/${each.value}:latest"

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.gcp_project_id
      }
      env {
        name  = "ALLOYDB_ENDPOINT"
        value = google_alloydb_instance.alloydb_primary.ip_address
      }
      env {
        name  = "DROPZONE_BUCKET"
        value = google_storage_bucket.dropzone_bucket.name
      }
    }

    service_account = google_service_account.agent_service_accounts[each.key].email
  }
}

# Allow Apex Orchestrator Router (or API Gateway) to invoke Cloud Run nodes
resource "google_cloud_run_v2_service_iam_member" "agent_invoker" {
  for_each = toset(var.agent_nodes)
  name     = google_cloud_run_v2_service.agent_services[each.value].name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.api_gateway_sa.email}"
}

# --------------------------------------------------------------------
# APEX DEPLOYMENT ROUTER & GATEWAY MANIFEST (API GATEWAY)
# --------------------------------------------------------------------
resource "google_service_account" "api_gateway_sa" {
  account_id   = "unykorn-api-gateway-sa"
  display_name = "Service Account for Unykorn API Gateway Router"
}

# Bind Vertex AI Agent builder invoker permissions to Gateway SA (for Apex Router)
resource "google_project_iam_member" "gateway_vertex_ai" {
  project = var.gcp_project_id
  role    = "roles/discoveryengine.admin" # Required for Vertex AI Agent Builder control
  member  = "serviceAccount:${google_service_account.api_gateway_sa.email}"
}

resource "google_api_gateway_api" "routing_api" {
  provider = google
  api_id   = "unykorn-doc-intel-api"
}

resource "google_api_gateway_api_config" "routing_config" {
  provider      = google
  api           = google_api_gateway_api.routing_api.api_id
  api_config_id = "unykorn-api-config-v1"

  openapi_documents {
    document {
      path     = "api-gateway-openapi.yaml"
      contents = filebase64("${path.module}/../api-gateway-openapi.yaml")
    }
  }

  gateway_device_iam_binding {
    role = "roles/apigateway.viewer"
    members = [
      "serviceAccount:${google_service_account.api_gateway_sa.email}"
    ]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_api_gateway_gateway" "api_gateway" {
  provider   = google
  api_config = google_api_gateway_api_config.routing_config.id
  gateway_id = "unykorn-gateway"
  region     = var.region
}

# --------------------------------------------------------------------
# OUTPUTS
# --------------------------------------------------------------------
output "api_gateway_url" {
  value       = google_api_gateway_gateway.api_gateway.default_hostname
  description = "The public URL of the deployed API Gateway routing fabric."
}

output "evidence_vault_uri" {
  value       = google_storage_bucket.cold_storage_vault.url
  description = "Cold storage legal lockup location."
}

output "dropzone_upload_uri" {
  value       = google_storage_bucket.dropzone_bucket.url
  description = "Dropzone bucket for PDF/JSON context ingestion."
}
