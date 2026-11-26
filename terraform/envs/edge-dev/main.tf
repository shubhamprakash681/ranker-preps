locals {
  gcp_api_host = trimprefix(trimprefix(var.gcp_api_url, "https://"), "http://")
}

module "edge" {
  source = "../../modules/edge"

  name_prefix          = var.name_prefix
  env                  = var.env
  aws_alb_dns_name     = var.aws_alb_dns_name
  gcp_api_host         = local.gcp_api_host
  origin_verify_secret = var.origin_verify_secret
  username             = var.username
  gcp_project_id       = var.gcp_project_id
  repo_url             = var.repo_url
}
