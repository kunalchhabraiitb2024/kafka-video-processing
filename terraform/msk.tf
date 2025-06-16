# MSK (Managed Streaming for Kafka) Configuration
resource "aws_msk_cluster" "video_pipeline" {
  cluster_name           = "video-pipeline-kafka"
  kafka_version          = "2.8.1"
  number_of_broker_nodes = 2

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = [aws_subnet.private[0].id, aws_subnet.private[1].id]
    storage_info {
      ebs_storage_info {
        volume_size = 10
      }
    }
    security_groups = [aws_security_group.msk.id]
  }

  encryption_info {
    encryption_at_rest_kms_key_id = aws_kms_key.msk.arn
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.video_pipeline.arn
    revision = aws_msk_configuration.video_pipeline.latest_revision
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = {
    Name = "video-pipeline-kafka"
  }
}

resource "aws_msk_configuration" "video_pipeline" {
  kafka_versions = ["2.8.1"]
  name           = "video-pipeline-config"

  server_properties = <<PROPERTIES
auto.create.topics.enable=true
default.replication.factor=2
min.insync.replicas=1
num.partitions=3
PROPERTIES
}

resource "aws_kms_key" "msk" {
  description = "MSK encryption key"
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/video-pipeline"
  retention_in_days = 7
}

# Security group for MSK
resource "aws_security_group" "msk" {
  name_prefix = "msk-sg"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "msk-security-group"
  }
}

# Output MSK connection details
output "msk_bootstrap_brokers" {
  value = aws_msk_cluster.video_pipeline.bootstrap_brokers
}

output "msk_bootstrap_brokers_tls" {
  value = aws_msk_cluster.video_pipeline.bootstrap_brokers_tls
}
