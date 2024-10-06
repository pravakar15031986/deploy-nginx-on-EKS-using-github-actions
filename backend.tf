terraform {
  backend "s3" {
    bucket = "terraform-statefile-backup-storage"
    key    = "eks-cluster/terraform.tfstate"
    region = "us-east-1"
  }
}
