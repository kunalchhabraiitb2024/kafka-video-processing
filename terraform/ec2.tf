# EC2 instance for RTSP server (FREE TIER)
resource "aws_instance" "rtsp_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type  # t2.micro for free tier
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.rtsp.id]
  key_name               = aws_key_pair.main.key_name
  
  associate_public_ip_address = true

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    s3_bucket = aws_s3_bucket.video_output.bucket
  }))

  tags = merge(local.common_tags, {
    Name = "${local.name}-rtsp-server"
  })
}

# Data source for Amazon Linux AMI (FREE TIER)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Key pair for EC2 access (using key from main.tf)
# aws_key_pair.main is defined in main.tf

# Security group for RTSP server
resource "aws_security_group" "rtsp" {
  name_prefix = "${local.name}-rtsp-"
  vpc_id      = aws_vpc.main.id

  # RTSP port
  ingress {
    from_port   = 8554
    to_port     = 8554
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP for health checks
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# Output EC2 details
output "rtsp_server_ip" {
  description = "Public IP of RTSP server"
  value       = aws_instance.rtsp_server.public_ip
}

output "rtsp_server_private_ip" {
  description = "Private IP of RTSP server"
  value       = aws_instance.rtsp_server.private_ip
}
