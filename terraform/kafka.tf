# Kafka on EC2 with t3.medium for better memory
resource "aws_instance" "kafka" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.kafka_instance_type  # t3.medium for Kafka memory requirements
  key_name      = aws_key_pair.main.key_name
  iam_instance_profile = aws_iam_instance_profile.s3_access_profile.name
  
  vpc_security_group_ids      = [aws_security_group.kafka.id]
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  
  user_data = base64encode(templatefile("${path.module}/kafka_user_data.sh", {
    kafka_version = "2.13-3.5.0"
  }))

  tags = merge(local.common_tags, {
    Name = "${local.name}-kafka"
  })
}

resource "aws_security_group" "kafka" {
  name_prefix = "${local.name}-kafka-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6379
    to_port     = 6379
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

# Output Kafka connection details
output "kafka_bootstrap_servers" {
  value = "${aws_instance.kafka.private_ip}:9092"
}

output "kafka_public_ip" {
  value = aws_instance.kafka.public_ip
}
