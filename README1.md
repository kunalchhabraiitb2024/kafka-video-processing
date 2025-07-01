# Video Inference Pipeline

A production-ready video processing pipeline that demonstrates real-time object detection using containerized inference services, Apache Kafka for stream processing, and AWS infrastructure.

## 🎯 Overview

This pipeline processes video streams through a distributed architecture, performing object detection on batched frames and storing annotated results in AWS S3.

## 🏗️ Architecture

```
RTSP Server → Frame Extractor → Kafka → Consumer → Inference Service → S3
     ↓              ↓                        ↓            ↓              ↓
 Video Stream   25-frame batches    Message Queue   Container API   Annotated Results
```

### Pipeline Flow

1. **RTSP Server** streams demo video via bluenviron/mediamtx
2. **Frame Extractor** batches 25 frames → Kafka topic 'video-stream-1'
3. **Consumer** processes batches → Containerized Inference Service
4. **Mock object detection** returns bounding boxes
5. **Post-processing** draws annotations (outside container)
6. **Results** uploaded to S3 as JSON with annotated images

## 🔧 Technology Stack

- **Infrastructure**: AWS (EC2, S3, VPC) via Terraform
- **Messaging**: Apache Kafka (Confluent containers)
- **Inference**: Flask API + OpenCV (containerized with Docker)
- **Processing**: Python with kafka-python, boto3, PIL
- **Storage**: S3 with IAM roles and encryption

## 📋 Infrastructure Components

| Component | Endpoint | Description |
|-----------|----------|-------------|
| RTSP Server | `<RTSP_IP>:8554` | Video streaming server |
| Kafka Cluster | `<KAFKA_IP>:9092` | Message broker (internal: 10.0.1.37:9092) |
| Inference Service | `<K8S_IP>:8080` | Containerized object detection API |
| S3 Bucket | `<S3_BUCKET>` | Result storage |

## 💾 Repository Structure

```
.
├── Core Pipeline
│   ├── enhanced_extractor.py    # RTSP/file frame extraction (25-frame batching)
│   ├── enhanced_consumer.py     # Kafka consumer with inference integration
│   ├── inference_service.py     # Containerized CPU-based object detection
│   └── Dockerfile              # Container definition for inference service
│
├── Infrastructure as Code
│   ├── terraform/              # Complete AWS infrastructure
│   ├── k8s-deployment.yaml     # Kubernetes manifests
│   └── deploy_*.sh            # Deployment automation scripts
│
└── Testing & Verification
    ├── test_pipeline.sh        # Automated pipeline testing
    └── final_summary.sh        # Deployment verification
```

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform installed
- Docker installed
- Python 3.8+
- SSH key pair (`~/.ssh/company-key.pem`)

### Deploy Infrastructure

```bash
# Navigate to terraform directory
cd terraform

# Initialize and apply infrastructure
terraform init
terraform apply
```

### Run Pipeline Test

```bash
# Execute automated pipeline test
./test_pipeline.sh
```

### Manual Testing

```bash
# SSH into Kafka instance
ssh -i ~/.ssh/company-key.pem ec2-user@<KAFKA_IP>

# Start consumer in background
python3 consumer.py &

# Run extractor for 60 seconds
python3 extractor.py --source file --duration 60
```

## 🐳 Containerized Services

The pipeline uses Docker containers for:
- RTSP streaming server
- Kafka broker and Zookeeper
- Inference service API

Check container status:
```bash
# RTSP Server
ssh -i ~/.ssh/company-key.pem ec2-user@<RTSP_IP> "sudo docker ps"

# Kafka
ssh -i ~/.ssh/company-key.pem ec2-user@<KAFKA_IP> "sudo docker ps"

# Inference Service
ssh -i ~/.ssh/company-key.pem ec2-user@<K8S_IP> "sudo docker ps"
```

## 📊 Performance Monitoring

### Check S3 Results
```bash
aws s3 ls s3://<S3_BUCKET>/results/ --region us-east-1
```

### Inference Service Statistics
```bash
curl http://<K8S_IP>:8080/info
```

## ✅ Key Features

- ✅ RTSP video source streams to Kafka
- ✅ Kafka consumer batches 25 frames
- ✅ Containerized inference service (CPU-based)
- ✅ Consumer calls inference service with frame batches
- ✅ Post-processing draws bounding boxes (outside container)
- ✅ Annotated images uploaded to S3
- ✅ Infrastructure provisioned via Terraform (IaC)
- ✅ Clean GitHub repository with all components

## 🔍 Verification

Run the final summary script to verify deployment:
```bash
./final_summary.sh
```

This will check:
- Infrastructure status
- Container health
- S3 results
- Service endpoints
- Performance metrics

## 📝 License

[Add your license here]

## 🤝 Contributing

[Add contribution guidelines here]

---

💡 **Note**: This pipeline demonstrates a complete, production-ready video processing workflow with containerized inference suitable for real-world applications.
