// Terraform example: GCP Secret Manager + IAM minimal bindings

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_kms_key_ring" "secret_ring" {
  name     = "officeiq-secret-ring"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "secret_key" {
  name     = "officeiq-secret-key"
  key_ring = google_kms_key_ring.secret_ring.id
  purpose  = "ENCRYPT_DECRYPT"

  rotation {
    rotation_period = "7776000s" // 90 days
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret" "example_secret" {
  secret_id = "${var.environment}-example-secret"
  project   = var.project_id

  replication {
    automatic = true
  }

  labels = {
    managed-by  = "terraform"
    nist-control = "sc-12"
  }
}

resource "google_secret_manager_secret_version" "example_secret_version" {
  secret      = google_secret_manager_secret.example_secret.id
  secret_data = var.example_secret_value
}

# Minimal IAM binding for a dedicated CI service account
resource "google_service_account" "ci_gsm_sa" {
  account_id   = "sa-ci-gsm"
  display_name = "CI GSM accessor"
  project      = var.project_id
}

resource "google_secret_manager_secret_iam_member" "ci_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.example_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.ci_gsm_sa.email}"
}

output "example_secret_name" {
  value = google_secret_manager_secret.example_secret.secret_id
}
