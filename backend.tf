terraform {
  backend "s3" {
    bucket = "terraform-statefile-backup-storage"
    key    = "eks-cluster/terraform.tfstate"
    region = "eu-north-1"
  }
}
