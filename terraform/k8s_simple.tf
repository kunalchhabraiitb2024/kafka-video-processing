# Simple EC2-based Kubernetes alternative (FREE TIER)
# Instead of EKS, we'll use Docker Compose on EC2 for cost savings

resource "aws_instance" "k8s_node" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type  # t2.micro for free tier
  key_name      = aws_key_pair.main.key_name
  
  vpc_security_group_ids      = [aws_security_group.k8s_node.id]
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  
  user_data = base64encode(templatefile("${path.module}/k8s_node_user_data.sh", {
    s3_bucket = aws_s3_bucket.video_output.bucket
    kafka_ip  = aws_instance.kafka.private_ip
  }))

  tags = merge(local.common_tags, {
    Name = "${local.name}-k8s-node"
  })
}

resource "aws_security_group" "k8s_node" {
  name_prefix = "${local.name}-k8s-"
  vpc_id      = aws_vpc.main.id

  # HTTP ports for services
  ingress {
    from_port   = 8000
    to_port     = 8002
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
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

output "k8s_node_ip" {
  description = "Public IP of K8s node"
  value       = aws_instance.k8s_node.public_ip
}
