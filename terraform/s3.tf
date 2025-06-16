# S3 bucket for storing processed video frames
resource "aws_s3_bucket" "video_output" {
  bucket = "optifye-video-output-${random_string.bucket_suffix.result}"

  tags = {
    Name = "video-output-bucket"
  }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "video_output" {
  bucket = aws_s3_bucket.video_output.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "video_output" {
  bucket = aws_s3_bucket.video_output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM role for services to access S3
resource "aws_iam_role" "s3_access_role" {
  name = "video-pipeline-s3-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["ec2.amazonaws.com", "eks.amazonaws.com"]
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3-access-policy"
  role = aws_iam_role.s3_access_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.video_output.arn,
          "${aws_s3_bucket.video_output.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "s3_access_profile" {
  name = "video-pipeline-s3-profile"
  role = aws_iam_role.s3_access_role.name
}

# Output S3 bucket name
output "s3_bucket_name" {
  value = aws_s3_bucket.video_output.bucket
}
