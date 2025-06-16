output "rtsp_public_ip" {
  description = "Public IP of the RTSP EC2 instance"
  value       = aws_instance.rtsp.public_ip
}

output "kafka_public_ip" {
  description = "Public IP of the Kafka EC2 instance"
  value       = aws_instance.kafka.public_ip
}

output "k8s_public_ip" {
  description = "Public IP of the K8s/Inference EC2 instance"
  value       = aws_instance.k8s.public_ip
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for inference outputs"
  value       = aws_s3_bucket.inference_outputs.bucket
}
