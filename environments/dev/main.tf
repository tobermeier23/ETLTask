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
  account_id   = "etlpipeline"
  display_name = "ETL SA"
  description  = "user-managed service account for Composer and Dataflow"
  project = var.project_id
  depends_on = [google_project_service.all]
}

resource "google_project_iam_member" "allbuild" {
  project    = var.project_id
  for_each   = toset(var.build_roles_list)
  role       = each.key
  member     = "serviceAccount:${google_service_account.etl.email}"
  depends_on = [google_project_service.all,google_service_account.etl]
}

resource "google_project_iam_member" "composerAgent" {
  project    = var.project_id
  role       = "roles/composer.ServiceAgentV2Ext"
  member     = "serviceAccount:service-${var.project_number}@cloudcomposer-accounts.iam.gserviceaccount.com"
  depends_on = [google_project_service.all]
}

# Create Core Composer environment
resource "google_composer_environment" "fred" {
  project   = var.project_id
  name      = "fred"
  region    = var.region
  config {

    software_config {
      image_version = "composer-3-airflow-2.10.5"
      env_variables = {
        AIRFLOW_VAR_PROJECT_ID  = var.project_id
        AIRFLOW_VAR_GCE_ZONE    = var.zone
        AIRFLOW_VAR_BUCKET_PATH = "gs://fred-${var.project_id}-files"
      }
    }
    node_config {
      service_account = google_service_account.etl.name
    }
  }
  depends_on = [google_project_service.all, google_service_account.etl, google_project_iam_member.allbuild, google_project_iam_member.composerAgent]
}

# Create CI/CD Composer environment
resource "google_composer_environment" "world-bank" {
  project   = var.project_id
  name      = "world-bank"
  region    = var.region
  config {

    software_config {
      image_version = "composer-3-airflow-2.10.5"
      env_variables = {
        AIRFLOW_VAR_PROJECT_ID  = var.project_id
        AIRFLOW_VAR_GCE_ZONE    = var.zone
        AIRFLOW_VAR_BUCKET_PATH = "gs://world-bank-${var.project_id}-files"
      }
    }
    node_config {
      service_account = google_service_account.etl.name
    }
  }
  depends_on = [google_project_service.all, google_service_account.etl, google_project_iam_member.allbuild, google_project_iam_member.composerAgent]
}

resource "google_bigquery_dataset" "icnsa_dataset" {
  project    = var.project_id
  dataset_id = "icnsa"
  location   = "US"
  depends_on = [google_project_service.all]
}

resource "google_bigquery_dataset" "world_bank_dataset" {
  project    = var.project_id
  dataset_id = "world_bank_life_expectancy"
  location   = "US"
  depends_on = [google_project_service.all]
}

resource "google_bigquery_table" "icnsa_table" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.icnsa_dataset.dataset_id
  table_id   = "icnsa"
  deletion_protection = false

  schema     = <<EOF
[
  {
    "name": "observation_date",
    "type": "DATE",
    "mode": "REQUIRED"
  },
  {
    "name": "ICSA",
    "type": "INTEGER",
    "mode": "REQUIRED"
  }  
]
EOF
  depends_on = [google_bigquery_dataset.icnsa_dataset]
}

resource "google_bigquery_table" "icnsa_bad_table" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.icnsa_dataset.dataset_id
  table_id   = "bad_icnsa"
  deletion_protection = false

  schema     = <<EOF
[
  {
    "name": "observation_date",
    "type": "DATE",
    "mode": "REQUIRED"
  },
  {
    "name": "ICSA",
    "type": "INTEGER",
    "mode": "REQUIRED"
  }  
]
EOF
  depends_on = [google_bigquery_dataset.icnsa_dataset]
}

# Create Cloud Storage bucket and add files
resource "google_storage_bucket" "pipeline_files" {
  project       = var.project_number
  name          = "fred-${var.project_id}-files"
  location      = "US"
  force_destroy = true
  depends_on    = [google_project_service.all]
}

resource "google_storage_bucket_object" "json_schema" {
  name       = "jsonSchema.json"
  source     = "${path.module}/files/ETLTaskjsonSchema.json"
  bucket     = google_storage_bucket.pipeline_files.name
  depends_on = [google_storage_bucket.pipeline_files]
}

resource "google_storage_bucket_object" "bad_json_schema" {
  name       = "BadjsonSchema.json"
  source     = "${path.module}/files/BadETLTaskjsonSchema.json"
  bucket     = google_storage_bucket.pipeline_files.name
  depends_on = [google_storage_bucket.pipeline_files]
}

resource "google_storage_bucket_object" "input_file" {
  name       = "icnsa_data.csv"
  source     = "${path.module}/files/ETLTaskinputFile.txt"
  bucket     = google_storage_bucket.pipeline_files.name
  depends_on = [google_storage_bucket.pipeline_files]
}

data "google_composer_environment" "example" {
  project    = var.project_id
  region     = var.region
  name       = google_composer_environment.fred.name
  depends_on = [google_composer_environment.fred]
}

resource "google_storage_bucket_object" "dag_file" {
  name       = "dags/composer-dataflow-dag.py"
  source     = "${path.module}/files/composer-dataflow-dag.py"
  bucket     = replace(replace(data.google_composer_environment.example.config.0.dag_gcs_prefix, "gs://", ""),"/dags","")
  depends_on = [google_composer_environment.fred, google_storage_bucket.pipeline_files, google_bigquery_table.icnsa_table]
}