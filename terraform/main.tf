terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables (FREE TIER OPTIMIZED)
variable "aws_region" {
  description = "AWS region for free tier"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "optifye-cluster"
}

variable "instance_type" {
  description = "EC2 instance type (free tier)"
  type        = string
  default     = "t2.micro"
}

variable "k8s_instance_type" {
  description = "K8s instance type (needs more resources)"
  type        = string
  default     = "t3.medium"
}

variable "kafka_instance_type" {
  description = "Kafka instance type (needs more memory)"
  type        = string
  default     = "t3.medium"
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Local values
locals {
  name = "optifye-video-pipeline"
  common_tags = {
    Project     = "OptifyeVideoPipeline"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# Random suffix for unique resource names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 Bucket for video output (FREE)
# Key pair for EC2 instances
resource "aws_key_pair" "main" {
  key_name   = "${local.name}-key"
  public_key = file("~/.ssh/optifye-key.pub")
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}