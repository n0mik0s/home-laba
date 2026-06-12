terraform {
  backend "s3" {
    bucket = "laba"
    key    = "laba/terraform.tfstate"
    region = "main"

    endpoints = {
      s3 = "https://s3-api.personal.org.ua"
    }

    # Credentials via environment variables:
    # AWS_ACCESS_KEY_ID
    # AWS_SECRET_ACCESS_KEY

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
