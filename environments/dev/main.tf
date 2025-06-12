resource "google_cloud_run_v2_service" "default" {
  project = var.project_id
  name     = "cloudrun-service"
  location = "us-central1"
  deletion_protection = false
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      base_image_uri = "us-central1-docker.pkg.dev/serverless-runtimes/google-22-full/runtimes/python313"
      volume_mounts {
        name = "gcs-1"
        mount_path = "/fredfiles"
      }
    }

    volumes {
      name = "gcs-1"
      gcs {
        bucket = "fred-ninth-sol-462415-k7-files"
        read_only = false
      }
    }
  }
  build_config {
    #source_location = "gs://${google_storage_bucket.bucket.name}/${google_storage_bucket_object.object.name}"
    source_location = "gs://fred-run-source-location/fred-main.py"
    function_target = "hello_http"
    image_uri = "us-docker.pkg.dev/cloudrun/container/hello"
    base_image = "us-central1-docker.pkg.dev/serverless-runtimes/google-22-full/runtimes/python313"
    enable_automatic_updates = true
    #worker_pool = "worker-pool"
    service_account = google_service_account.cloudbuild_service_account.id
  }
  depends_on = [
    google_project_iam_member.act_as,
    google_project_iam_member.logs_writer
  ]
}

#data "google_project" "project" {
#}

resource "google_storage_bucket" "bucket" {
  name     = "fred-run-source-location"  # Every bucket name must be globally unique
  project = var.project_id
  location = "US"
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "object" {
  name   = "fred-main.zip"
  bucket = google_storage_bucket.bucket.name
  source = "${path.root}/files/fred-main.zip"  # Add path to the zipped function source code
}

resource "google_storage_bucket" "pipeline_files" {
  project       = var.project_number
  name          = "fred-${var.project_id}-files"
  location      = "US"
  force_destroy = true
  depends_on    = [google_project_service.all]
}

resource "google_service_account" "cloudbuild_service_account" {
  account_id = "build-sa"
  project = var.project_id
}

resource "google_project_iam_member" "act_as" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloudbuild_service_account.email}"
}

resource "google_project_iam_member" "logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild_service_account.email}"
}

variable "gcp_service_list" {
  description = "The list of apis necessary for the project"
  type        = list(string)
  default = [
    "dataflow.googleapis.com",
    "compute.googleapis.com",
    "composer.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "iam.googleapis.com"
  ]
}

resource "google_project_service" "all" {
  for_each           = toset(var.gcp_service_list)
  project            = var.project_number
  service            = each.key
  disable_on_destroy = false
}

resource "google_service_account" "etl" {
  account_id   = "etlpipelinetask"
  display_name = "ETL SA"
  description  = "user-managed service account for Composer and Dataflow"
  project = var.project_id
  depends_on = [google_project_service.all]
}