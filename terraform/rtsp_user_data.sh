#!/bin/bash
# Install Docker
yum update -y
amazon-linux-extras install docker -y
service docker start
usermod -a -G docker ec2-user

# Pull and run bluenviron/mediamtx (formerly rtsp-simple-server)
docker run -d --name mediamtx -p 554:554 -p 8554:8554 -v /opt/mediamtx.yml:/mediamtx.yml bluenviron/mediamtx:latest

# (Optional) Copy demo video to instance and configure mediamtx for looping stream
# Example: aws s3 cp s3://your-bucket/demo.mp4 /opt/demo.mp4
# Configure mediamtx.yml as needed for your stream
