resource "google_cloud_run_v2_service" "default" {
  project = var.project_id
  name     = "fred-service-new"
  location = "us-central1"
  deletion_protection = false
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "us-central1-docker.pkg.dev/ninth-sol-462415-k7/cloud-run-source-deploy/fred-download"
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
    source_location = "gs://fred-run-source-location/fred-main.zip"
    function_target = "hello_http"
    image_uri = "us-central1-docker.pkg.dev/ninth-sol-462415-k7/cloud-run-source-deploy/fred-download"
    base_image = "us-central1-docker.pkg.dev/serverless-runtimes/google-22-full/runtimes/python313"
    enable_automatic_updates = true
    service_account = google_service_account.cloudbuild_service_account.id
  }
  depends_on = [
    google_project_iam_member.act_as,
    google_project_iam_member.logs_writer
  ]
}

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

resource "google_eventarc_trigger" "fred-trigger" {
  name     = "fred-trigger"
  project            = var.project_number
  location = "us-central1"
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }
  matching_criteria {
    attribute = "serviceName"
    value     = "cloudbuild.googleapis.com"
  }
  matching_criteria {
    attribute = "methodName"
    value     = "google.devtools.cloudbuild.v1.CloudBuild.CreateBuild"
  }
  service_account = "etlpipeline@ninth-sol-462415-k7.iam.gserviceaccount.com"
  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.default.name
      region  = "us-central1"
      path    = "/"
    }
  }
}

resource "google_bigquery_dataset" "fred_dataset" {
  project    = var.project_id
  dataset_id = "fred_icnsa"
  location   = "US"
}

resource "google_bigquery_table" "fred_table" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.fred_dataset.dataset_id
  table_id   = "fred_icnsa"
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
  depends_on = [google_bigquery_dataset.fred_dataset]
}

resource "google_bigquery_table" "fred_bad_table" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.fred_dataset.dataset_id
  table_id   = "fred_bad_icnsa"
  deletion_protection = false

  schema     = <<EOF
[
  {
      "name": "RawContent",
      "type": "STRING"
  },
  {
      "name": "ErrorMsg",
      "type": "STRING"
  }  
]
EOF
  depends_on = [google_bigquery_dataset.fred_dataset]
}

# Create Cloud Storage bucket and add files
resource "google_storage_bucket" "fred_dataflow_files" {
  project       = var.project_number
  name          = "fred-dataflow-files"
  location      = "US"
  force_destroy = true
  uniform_bucket_level_access = true
  hierarchical_namespace {
    enabled = true
  }
  depends_on    = [google_project_service.all]
}

resource "google_storage_bucket_object" "json_schema" {
  name       = "jsonSchema.json"
  source     = "${path.root}/files/fredJsonSchema.json"
  bucket     = google_storage_bucket.fred_dataflow_files.name
  depends_on = [google_storage_bucket.fred_dataflow_files]
}

resource "google_storage_bucket_object" "bad_json_schema" {
  name       = "BadjsonSchema.json"
  source     = "${path.root}/files/fredBadJsonSchema.json"
  bucket     = google_storage_bucket.fred_dataflow_files.name
  depends_on = [google_storage_bucket.fred_dataflow_files]
}

resource "google_storage_folder" "fred_tmp_folder" {
  bucket        = google_storage_bucket.fred_dataflow_files.name
  name          = "tmp/"
}

resource "google_data_pipeline_pipeline" "primary" {
  name         = "fred-ingest"
  display_name = "fred-ingest"
  project      = var.project_id
  type         = "PIPELINE_TYPE_BATCH"
  state        = "STATE_ACTIVE"
  region       = "us-central1"

  workload {
    dataflow_launch_template_request {
      project_id = var.project_number
      gcs_path   = "gs://dataflow-templates-us-central1/latest/GCS_CSV_to_BigQuery"
      launch_parameters {
        job_name = "fred-ingest"
        parameters = {
          "inputFilePattern" : "gs://fred-ninth-sol-462415-k7-files/fred_input.csv"
          "schemaJSONPath" : "gs://fred-dataflow-files/jsonSchema.json"
          "outputTable" : "ninth-sol-462415-k7.fred_icnsa.fred_icnsa"
          "badRecordsOutputTable" : "ninth-sol-462415-k7.fred_icnsa.fred_bad_icnsa"
          "csvFormat" : "Default"
          "delimiter" : ","
          "bigQueryLoadingTemporaryDirectory" : "gs://fred-dataflow-files/tmp"
          "containsHeaders" : "true"
          "csvFileEncoding" : "UTF-8"
        }
        environment {
          temp_location = "gs://fred-dataflow-files/tmp"
          num_workers = 5
          max_workers = 5
          service_account_email = "etlpipeline@ninth-sol-462415-k7.iam.gserviceaccount.com"
          machine_type = "n1-standard-1"
          worker_region = "us-east5"
          worker_zone = "us-east5-c"
        }
        update                 = false
      }
      location = "us-central1"
    }
  }
  schedule_info {
    schedule  = "0 * * * *"
    time_zone = "America/Chicago"
  }
}

resource "google_storage_bucket" "wb_bucket" {
  name     = "wb-run-source-location"  # Every bucket name must be globally unique
  project = var.project_id
  location = "US"
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "wb_run_files" {
  name   = "wb-main.zip"
  bucket = google_storage_bucket.wb_bucket.name
  source = "${path.root}/files/wb-main.zip"  # Add path to the zipped function source code
}

resource "google_storage_bucket" "wb_pipeline_files" {
  project       = var.project_number
  name          = "wb-${var.project_id}-files"
  location      = "US"
  force_destroy = true
  depends_on    = [google_project_service.all]
}

resource "google_cloud_run_v2_service" "wb_run_service" {
  project = var.project_id
  name     = "wb-service"
  location = "us-central1"
  deletion_protection = false
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "us-central1-docker.pkg.dev/ninth-sol-462415-k7/cloud-run-source-deploy/wb-service"
      base_image_uri = "us-central1-docker.pkg.dev/serverless-runtimes/google-22-full/runtimes/python313"
      volume_mounts {
        name = "gcs-1"
        mount_path = "/wbfiles"
      }
    }

    volumes {
      name = "gcs-1"
      gcs {
        bucket = "wb-ninth-sol-462415-k7-files"
        read_only = false
      }
    }
  }
  build_config {
    source_location = "gs://wb-run-source-location/wb-main.zip"
    function_target = "hello_http"
    image_uri = "us-central1-docker.pkg.dev/ninth-sol-462415-k7/cloud-run-source-deploy/wb-service"
    base_image = "us-central1-docker.pkg.dev/serverless-runtimes/google-22-full/runtimes/python313"
    enable_automatic_updates = true
    service_account = google_service_account.cloudbuild_service_account.id
  }
  depends_on = [
    google_project_iam_member.act_as,
    google_project_iam_member.logs_writer
  ]
}

resource "google_eventarc_trigger" "wb-trigger" {
  name     = "wb-trigger"
  project  = var.project_number
  location = "us-central1"
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }
  matching_criteria {
    attribute = "serviceName"
    value     = "cloudbuild.googleapis.com"
  }
  matching_criteria {
    attribute = "methodName"
    value     = "google.devtools.cloudbuild.v1.CloudBuild.CreateBuild"
  }
  service_account = "etlpipeline@ninth-sol-462415-k7.iam.gserviceaccount.com"
  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.wb_run_service.name
      region  = "us-central1"
      path    = "/"
    }
  }
}

resource "google_bigquery_dataset" "wb_dataset" {
  project    = var.project_id
  dataset_id = "wb_data"
  location   = "US"
}

resource "google_bigquery_table" "wb_table" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.wb_dataset.dataset_id
  table_id   = "wb_data"
  deletion_protection = false

  schema     = <<EOF
[
  {
    "name": "Data Source",
    "type": "STRING"
  },
  {
    "name": "World Development Indicators",
    "type": "STRING"
  },
  {
    "name": "Country Name",
    "type": "STRING"
  },
  {
    "name": "Country Code",
    "type": "STRING"
  },
  {
    "name": "Inticator Name",
    "type": "STRING"
  },
  {
    "name": "Indicator Code",
    "type": "STRING"
  },
  {
    "name": "1960",
    "type": "INTEGER"
  },
  {
    "name": "1961",
    "type": "INTEGER"
  },
  {
    "name": "1962",
    "type": "INTEGER"
  },
  {
    "name": "1963",
    "type": "INTEGER"
  },
  {
    "name": "1964",
    "type": "INTEGER"
  },
  {
    "name": "1965",
    "type": "INTEGER"
  },
  {
    "name": "1966",
    "type": "INTEGER"
  },
  {
    "name": "1967",
    "type": "INTEGER"
  },
  {
    "name": "1968",
    "type": "INTEGER"
  },
  {
    "name": "1969",
    "type": "INTEGER"
  },
  {
    "name": "1970",
    "type": "INTEGER"
  },
  {
    "name": "1971",
    "type": "INTEGER"
  },
  {
    "name": "1972",
    "type": "INTEGER"
  },
  {
    "name": "1973",
    "type": "INTEGER"
  },
  {
    "name": "1974",
    "type": "INTEGER"
  },
  {
    "name": "1975",
    "type": "INTEGER"
  },
  {
    "name": "1976",
    "type": "INTEGER"
  },
  {
    "name": "1977",
    "type": "INTEGER"
  },
  {
    "name": "1978",
    "type": "INTEGER"
  },
  {
    "name": "1979",
    "type": "INTEGER"
  },
  {
    "name": "1980",
    "type": "INTEGER"
  },
  {
    "name": "1981",
    "type": "INTEGER"
  },
  {
    "name": "1982",
    "type": "INTEGER"
  },
  {
    "name": "1983",
    "type": "INTEGER"
  },
  {
    "name": "1984",
    "type": "INTEGER"
  },
  {
    "name": "1985",
    "type": "INTEGER"
  },
  {
    "name": "1986",
    "type": "INTEGER"
  },
  {
    "name": "1987",
    "type": "INTEGER"
  },
  {
    "name": "1988",
    "type": "INTEGER"
  },
  {
    "name": "1989",
    "type": "INTEGER"
  },
  {
    "name": "1990",
    "type": "INTEGER"
  },
  {
    "name": "1991",
    "type": "INTEGER"
  },
  {
    "name": "1992",
    "type": "INTEGER"
  },
  {
    "name": "1993",
    "type": "INTEGER"
  },
  {
    "name": "1994",
    "type": "INTEGER"
  },
  {
    "name": "1995",
    "type": "INTEGER"
  },
  {
    "name": "1996",
    "type": "INTEGER"
  },
  {
    "name": "1997",
    "type": "INTEGER"
  },
  {
    "name": "1998",
    "type": "INTEGER"
  },
  {
    "name": "1999",
    "type": "INTEGER"
  },
  {
    "name": "2000",
    "type": "INTEGER"
  },
  {
    "name": "2001",
    "type": "INTEGER"
  },
  {
    "name": "2002",
    "type": "INTEGER"
  },
  {
    "name": "2003",
    "type": "INTEGER"
  },
  {
    "name": "2004",
    "type": "INTEGER"
  },
  {
    "name": "2005",
    "type": "INTEGER"
  },
  {
    "name": "2006",
    "type": "INTEGER"
  },
  {
    "name": "2007",
    "type": "INTEGER"
  },
  {
    "name": "2008",
    "type": "INTEGER"
  },
  {
    "name": "2009",
    "type": "INTEGER"
  },
  {
    "name": "2010",
    "type": "INTEGER"
  },
  {
    "name": "2011",
    "type": "INTEGER"
  },
  {
    "name": "2012",
    "type": "INTEGER"
  },
  {
    "name": "2013",
    "type": "INTEGER"
  },
  {
    "name": "2014",
    "type": "INTEGER"
  },
  {
    "name": "2015",
    "type": "INTEGER"
  },
  {
    "name": "2016",
    "type": "INTEGER"
  },
  {
    "name": "2017",
    "type": "INTEGER"
  },
  {
    "name": "2018",
    "type": "INTEGER"
  },
  {
    "name": "2019",
    "type": "INTEGER"
  },
  {
    "name": "2020",
    "type": "INTEGER"
  },
  {
    "name": "2021",
    "type": "INTEGER"
  },
  {
    "name": "2022",
    "type": "INTEGER"
  },
  {
    "name": "2023",
    "type": "INTEGER"
  },
  {
    "name": "2024",
    "type": "INTEGER"
  }
]
EOF
  depends_on = [google_bigquery_dataset.fred_dataset]
}

resource "google_bigquery_table" "wb_bad_table" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.wb_dataset.dataset_id
  table_id   = "wb_bad_data"
  deletion_protection = false

  schema     = <<EOF
[
  {
      "name": "RawContent",
      "type": "STRING"
  },
  {
      "name": "ErrorMsg",
      "type": "STRING"
  }  
]
EOF
  depends_on = [google_bigquery_dataset.fred_dataset]
}

# Create Cloud Storage bucket and add files
resource "google_storage_bucket" "wb_dataflow_files" {
  project       = var.project_number
  name          = "wb-dataflow-files"
  location      = "US"
  force_destroy = true
  uniform_bucket_level_access = true
  hierarchical_namespace {
    enabled = true
  }
  depends_on    = [google_project_service.all]
}

resource "google_storage_bucket_object" "wb_json_schema" {
  name       = "wbJsonSchema.json"
  source     = "${path.root}/files/wbJsonSchema.json"
  bucket     = google_storage_bucket.wb_dataflow_files.name
  depends_on = [google_storage_bucket.wb_dataflow_files]
}

resource "google_storage_bucket_object" "wb_bad_json_schema" {
  name       = "wbBadjsonSchema.json"
  source     = "${path.root}/files/wbBadJsonSchema.json"
  bucket     = google_storage_bucket.wb_dataflow_files.name
  depends_on = [google_storage_bucket.wb_dataflow_files]
}

resource "google_storage_folder" "wb_tmp_folder" {
  bucket        = google_storage_bucket.wb_dataflow_files.name
  name          = "tmp/"
}

resource "google_data_pipeline_pipeline" "wb_dataflow_pipeline" {
  name         = "wb-ingest"
  display_name = "wb-ingest"
  project      = var.project_id
  type         = "PIPELINE_TYPE_BATCH"
  state        = "STATE_ACTIVE"
  region       = "us-central1"

  workload {
    dataflow_launch_template_request {
      project_id = var.project_number
      gcs_path   = "gs://dataflow-templates-us-central1/latest/GCS_CSV_to_BigQuery"
      launch_parameters {
        job_name = "wb-ingest"
        parameters = {
          "inputFilePattern" : "gs://wb-ninth-sol-462415-k7-files/API_SP.DYN.LE00.IN_DS2_en_csv_v2_2579.csv"
          "schemaJSONPath" : "gs://wb-dataflow-files/wbjsonSchema.json"
          "outputTable" : "ninth-sol-462415-k7.wb_data.wb_data"
          "badRecordsOutputTable" : "ninth-sol-462415-k7.wb_data.wb_bad_data"
          "csvFormat" : "Default"
          "delimiter" : ","
          "bigQueryLoadingTemporaryDirectory" : "gs://wb-dataflow-files/tmp"
          "containsHeaders" : "true"
          "csvFileEncoding" : "UTF-8"
        }
        environment {
          temp_location = "gs://wb-dataflow-files/tmp"
          num_workers = 5
          max_workers = 5
          service_account_email = "etlpipeline@ninth-sol-462415-k7.iam.gserviceaccount.com"
          machine_type = "n1-standard-1"
          worker_region = "us-east5"
          worker_zone = "us-east5-c"
        }
        update                 = false
      }
      location = "us-central1"
    }
  }
  schedule_info {
    schedule  = "30 * * * *"
    time_zone = "America/Chicago"
  }
}