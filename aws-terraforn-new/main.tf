terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.13.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.30.0"
    }
  }
}


terraform {
  backend "s3" {
    bucket  = "terraformbuckerforstatefiles" # create s3 bucket to store statefile
    key     = "dev/terraform.tfstate"
    region  = "us-east-1"
    encrypt = false
  }
}


# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source               = "./vpc"
  vpc_cidr             = "10.0.0.0/16"
  vpc_name             = "terraform-vpc"
  cidr_public_subnet   = ["10.0.1.0/24", "10.0.2.0/24"]
  eu_availability_zone = ["us-east-1a", "us-east-1b"]
}

module "security_group" {
  source                   = "./security-groups"
  ec2_sg_name              = "SG for EC2 to enable SSH(22) and HTTP(80)"
  vpc_id                   = module.vpc.vpc_id
  public_subnet_cidr_block = module.vpc.public_subnet_cidr_blocks
}

module "ec2" {
  source             = "./ec2"
  ami_id             = "ami-04b4f1a9cf54c11d0" # Ubuntu 22.04 (us-east-1)
  instance_type      = "t2.micro"
  subnet_id          = element(module.vpc.public_subnet_ids, 0)
  security_group_ids = [module.security_group.sg_ec2_sg_ssh_http_id]
  key_name           = "deployer-key"
  private_key_path   = "~/.ssh/gcp_terraform_key"
}

module "eks" {
  source                 = "./eks"
  cluster_name           = "my-eks-cluster"
  subnet_ids             = module.vpc.public_subnet_ids
  cluster_sg_id          = module.security_group.eks_cluster_sg_id
  node_sg_id             = module.security_group.eks_node_sg_id
  ssh_key_name           = "deployer-key"
  ebs_csi_driver_version = "v1.40.1-eksbuild.1"
}

module "rds" {
  source                  = "./rds"
  db_identifier           = "my-rds-instance"
  db_name                 = "appdb"
  db_username             = "vijay"
  db_password             = "Password123" # Consider storing in secrets manager
  db_subnet_ids           = module.vpc.public_subnet_ids
  db_subnet_group_name    = "rds-subnet-group"
  security_group_id       = module.security_group.rds_mysql_sg_id
  allocated_storage       = 20
  storage_type            = "gp2"
  engine                  = "MySQL"
  engine_version          = "8.0.41"
  instance_class          = "db.t3.micro"
  backup_retention_period = 0
}


data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_name
}

module "helm" {
  source                  = "./helm"
  kubernetes_cluster_host = module.eks.kubernetes_cluster_host
  cluster_ca_certificate  = module.eks.cluster_ca_certificate
  access_token            = data.aws_eks_cluster_auth.eks.token
  release_name            = "my-helm-release"
  helm_repo               = "https://charts.bitnami.com/bitnami"
  helmchart_name          = "nginx"
  helmchart_version       = "15.1.5"
  namespace               = "my-namespace"
}


