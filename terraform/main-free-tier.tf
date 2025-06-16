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
resource "aws_s3_bucket" "video_output" {
  bucket = "${local.name}-output-${random_id.bucket_suffix.hex}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "video_output" {
  bucket = aws_s3_bucket.video_output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Key pair for EC2 instances
resource "aws_key_pair" "main" {
  key_name   = "${local.name}-key"
  public_key = file("~/.ssh/optifye-key.pub")
}

# Outputs
output "s3_bucket_name" {
  description = "S3 bucket for storing processed videos"
  value       = aws_s3_bucket.video_output.id
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}
