# Filter out local zones, which are not currently supported 
# with managed node groups

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.13.0"

  name = var.vpc_name

  cidr = var.vpc_cidr_block
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = var.private_subnet_cidr_blocks
  public_subnets  = var.public_subnet_cidr_blocks

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.2"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true


  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Additional security group rules
  cluster_security_group_additional_rules = {
  http_rule = {
    description                = "Allow HTTP traffic from the internet"
    protocol                   = "tcp"
    from_port                  = 80
    to_port                    = 80
    cidr_blocks                = ["0.0.0.0/0"]  # Allow HTTP from anywhere
    type                       = "ingress"
  },
  https_rule = {
    description                = "Allow HTTPS traffic from the internet"
    protocol                   = "tcp"
    from_port                  = 443
    to_port                    = 443
    cidr_blocks                = ["0.0.0.0/0"]  # Allow HTTPS from anywhere
    type                       = "ingress"
  },
  k8s_api_rule = {
    description                = "Allow access to the Kubernetes API"
    protocol                   = "tcp"
    from_port                  = 6443
    to_port                    = 6443
    cidr_blocks                = ["0.0.0.0/0"]  # Allow access from anywhere
    type                       = "ingress"
  }
}


  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t2.micro"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }

    two = {
      name = "node-group-2"

      instance_types = ["t2.micro"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}



# Retrieve EKS cluster information and ensure data source waits for cluster to be created

data "aws_eks_cluster" "myApp-cluster" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "myApp-cluster" {
  name = module.eks.cluster_name
}

#Kubernetes provider for Terraform to connect with AWS EKS Cluster

provider "kubernetes" {

  host                   = data.aws_eks_cluster.myApp-cluster.endpoint
  token                  = data.aws_eks_cluster_auth.myApp-cluster.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.myApp-cluster.certificate_authority[0].data)

}

#Kubernetes resources in Terraform

resource "kubernetes_namespace" "terraform-k8s" {

  metadata {
    name = "terraform-k8s"
  }
}

resource "kubernetes_deployment" "nginx" {

  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.terraform-k8s.metadata[0].name

  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:1.21.6"

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
      }
    }
  }
}



resource "kubernetes_service" "nginx" {

  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.terraform-k8s.metadata[0].name
  }

  spec {
    selector = {
      app = kubernetes_deployment.nginx.spec[0].template[0].metadata[0].labels.app
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }
}



