variable "project_number" {
    type = string
    default = "236606652434"
}

variable "project_id" {
    type = string
    default = "ninth-sol-462415-k7"
}

variable "region" {
    type = string
    default = "us-central1"
}

variable "zone" {
    type = string
    default = "us-central1-a"
}

variable "build_roles_list" {
  description = "The list of roles that Composer and Dataflow needs"
  type        = list(string)
  default = [
    "roles/composer.worker",
    "roles/dataflow.admin",
    "roles/dataflow.worker",
    "roles/bigquery.admin",
    "roles/storage.objectAdmin",
    "roles/dataflow.serviceAgent",
    "roles/composer.ServiceAgentV2Ext"
  ]
}