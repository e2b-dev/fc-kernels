variable "github_organization" {
  type    = string
  default = "e2b-dev"
}

variable "github_repository" {
  type    = string
  default = "fc-kernels"
}

variable "gcp_region" {
  type = string
}

variable "gcp_project_id" {
  description = "The project to deploy the cluster in"
  type        = string
}

variable "prefix" {
  description = "The prefix to use for all resources in this module"
  type        = string
}

variable "gcs_bucket_name" {
  description = "The name of the GCS bucket to store the dashboards"
  type        = string
  default     = "e2b-prod-public-builds"
}