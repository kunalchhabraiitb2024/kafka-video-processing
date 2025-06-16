output "rtsp_public_ip" {
  description = "Public IP of the RTSP EC2 instance"
  value       = aws_instance.rtsp_server.public_ip
}

output "k8s_public_ip" {
  description = "Public IP of the K8s/Inference EC2 instance"
  value       = aws_instance.k8s.public_ip
}
