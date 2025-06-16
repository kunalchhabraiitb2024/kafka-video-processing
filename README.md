# OptifYe Video Inference Pipeline

A complete end-to-end video processing pipeline that streams video frames through Kafka to a containerized inference service, with results stored in S3.

## Architecture

```
RTSP Stream → Frame Extractor → Kafka → Consumer → Inference Service → Post-processing → S3
```

## Infrastructure

- **RTSP Server**: EC2 t2.micro (54.172.95.48) - Streams video via RTSP on port 8554
- **Kafka Broker**: EC2 t2.micro (34.207.77.179) - Message queue on port 9092
- **Inference Service**: EC2 t2.micro (54.80.24.67) - Containerized ML service on port 8080
- **S3 Storage**: optifye-video-pipeline-output-9efa2ef2 bucket (us-east-1)

## Features

### ✅ Completed
- **AWS Infrastructure**: Deployed via Terraform on 3x t2.micro instances
- **RTSP Video Streaming**: bluenviron/mediamtx container serving video
- **Kafka Message Queue**: Batch processing of 25 frames per message
- **Containerized Inference**: Flask-based object detection service
- **S3 Integration**: Automated upload of results and annotated frames
- **Enhanced Processing**: Post-processing with bounding box annotations
- **Dual Source Support**: File-based and RTSP stream processing
- **Health Monitoring**: Comprehensive service health checks

### 🔄 In Progress
- **Kubernetes Deployment**: Migrating from Docker to proper K8s
- **RTSP Integration**: Real-time stream processing
- **Performance Optimization**: Batch processing improvements

## Quick Start

### Deploy Infrastructure
```bash
# Deploy AWS infrastructure with Terraform
cd terraform/
terraform init
terraform apply

# Deploy complete pipeline
./deploy_enhanced.sh
```

### Test Pipeline
```bash
# Verify end-to-end functionality
./verify_pipeline.sh

# Manual testing
ssh ec2-user@34.207.77.179 'python3 extractor.py --source file --duration 60'
ssh ec2-user@34.207.77.179 'python3 consumer.py'
```

### Monitor Results
```bash
# Check S3 bucket
aws s3 ls s3://optifye-video-pipeline-output-9efa2ef2/results/ --recursive

# View service logs
ssh ec2-user@34.207.77.179 'tail -f consumer_enhanced.log'
```

## Components

### Frame Extractor (`enhanced_extractor.py`)
- Supports both video files and RTSP streams
- Batches exactly 25 frames per Kafka message
- Configurable frame resolution and quality
- Robust error handling and reconnection

### Consumer Service (`enhanced_consumer.py`)
- Consumes frame batches from Kafka
- Calls inference service with timeout handling
- Post-processes results with bounding box annotations
- Uploads both JSON results and annotated images to S3

### Inference Service (`inference.py`)
- Flask-based REST API with `/health` and `/infer` endpoints
- Mock object detection returning realistic bounding boxes
- Containerized deployment with health checks
- Supports batch processing of up to 50 frames

### Infrastructure as Code (`terraform/`)
- Complete AWS setup: VPC, EC2, Security Groups, S3
- Automated user data scripts for service deployment
- Cost-optimized for t2.micro free tier usage

## API Endpoints

### Inference Service (port 8080)
- `GET /health` - Service health check
- `POST /infer` - Batch inference endpoint
- `GET /stats` - Service statistics

### RTSP Stream (port 8554)
- `rtsp://54.172.95.48:8554/video` - Main video stream

## Configuration

### Environment Variables
```bash
RTSP_IP=54.172.95.48
KAFKA_IP=34.207.77.179
K8S_IP=54.80.24.67
S3_BUCKET=optifye-video-pipeline-output-9efa2ef2
```

### Kafka Topics
- `video-stream-1` - Frame batch messages (3 partitions)

## Performance

- **Batch Size**: 25 frames per message
- **Processing Rate**: ~5-10 FPS end-to-end
- **Inference Latency**: 100-150ms per batch
- **Storage**: JSON results + annotated JPEG frames

## Cost Analysis

- **EC2 Instances**: 3x t2.micro (~$25/month, free tier eligible)
- **S3 Storage**: ~$0.50/month for results
- **Data Transfer**: Minimal (<$1/month)
- **Total**: <$30/month (free tier: <$5/month)

## Monitoring

```bash
# Service health
curl http://54.80.24.67:8080/health

# Kafka topic status
ssh ec2-user@34.207.77.179 'sudo docker exec kafka kafka-topics --list --bootstrap-server localhost:9092'

# S3 results count
aws s3 ls s3://optifye-video-pipeline-output-9efa2ef2/results/ --recursive | wc -l
```

## Troubleshooting

### Common Issues
1. **RTSP Connection Failed**: Check if mediamtx container is running
2. **Kafka Consumer Lag**: Monitor consumer group lag
3. **S3 Upload Failures**: Verify AWS credentials and bucket permissions
4. **Inference Timeout**: Check if inference service is responsive

### Debug Commands
```bash
# Check all containers
ssh ec2-user@54.172.95.48 'sudo docker ps'
ssh ec2-user@34.207.77.179 'sudo docker ps'
ssh ec2-user@54.80.24.67 'sudo docker ps'

# View logs
ssh ec2-user@34.207.77.179 'tail -f consumer_enhanced.log'
ssh ec2-user@54.80.24.67 'sudo docker logs inference'
```

## Development

### Local Testing
```bash
# Install dependencies
pip install kafka-python opencv-python-headless boto3 pillow flask

# Run components locally
python enhanced_extractor.py --source file --duration 30
python enhanced_consumer.py
python inference.py
```

### Adding New Features
1. Fork the repository
2. Create feature branch
3. Test with existing infrastructure
4. Submit pull request

## Timeline

- **Day 1**: Infrastructure setup and basic pipeline
- **Day 2**: Enhanced features and optimization
- **Demo**: Live end-to-end demonstration

## Contact

For questions about this implementation, please contact the development team.

## License

This project is part of the OptifYe take-home assignment.
