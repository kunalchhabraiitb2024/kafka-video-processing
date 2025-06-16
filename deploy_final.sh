#!/bin/bash
# OptifYe Complete Pipeline Deployment with Docker Inference Service
# RTSP → Kafka → Consumer → Docker Inference Service → S3

set -e

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
RTSP_IP="23.20.26.169"
KAFKA_IP="54.89.113.227" 
K8S_IP="52.201.251.231"
S3_BUCKET="optifye-video-output-o35wbr8c"
SSH_OPTS="-i ~/.ssh/optifye-key -o StrictHostKeyChecking=no -o ConnectTimeout=30"

echo -e "${BLUE}OptifYe Complete Pipeline Deployment${NC}"
echo -e "${BLUE}====================================${NC}"
echo -e "RTSP Server: ${RTSP_IP}"
echo -e "Kafka Server: ${KAFKA_IP}" 
echo -e "Inference Server: ${K8S_IP}"
echo -e "S3 Bucket: ${S3_BUCKET}"
echo ""

# Function to run command on instance
run_cmd() {
    local ip=$1
    local name=$2
    local command=$3
    echo -e "${YELLOW}[${name}]${NC} ${command}"
    ssh $SSH_OPTS ec2-user@$ip "$command"
}

# Function to copy file to instance
copy_file() {
    local ip=$1
    local name=$2
    local local_file=$3
    local remote_file=$4
    echo -e "${YELLOW}[${name}]${NC} Copying ${local_file} to ${remote_file}"
    scp $SSH_OPTS "$local_file" ec2-user@$ip:"$remote_file"
}

echo "STEP 1: Deploy Containerized Inference Service"
echo "=============================================="

# Copy inference service files
copy_file $K8S_IP "INFERENCE" "inference_service.py" "inference_service.py"
copy_file $K8S_IP "INFERENCE" "Dockerfile" "Dockerfile"
copy_file $K8S_IP "INFERENCE" "requirements_inference.txt" "requirements_inference.txt"

run_cmd $K8S_IP "INFERENCE" '
    echo "Setting up containerized inference service..."
    
    # Stop any existing containers
    sudo docker stop $(sudo docker ps -aq) || true
    sudo docker rm $(sudo docker ps -aq) || true
    
    # Build the inference service
    echo "Building inference service container..."
    sudo docker build -t optifye-inference:latest .
    
    # Run the containerized inference service
    echo "Starting containerized inference service..."
    sudo docker run -d --name inference-service \
        -p 8080:8080 \
        --memory=1g \
        --restart unless-stopped \
        optifye-inference:latest
    
    sleep 10
    
    echo "✓ Containerized inference service deployed"
    sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    # Test the service
    echo "Testing inference service..."
    curl -s http://localhost:8080/health | python3 -m json.tool
'

echo ""
echo "STEP 2: Ensure Kafka is Running"
echo "==============================="

run_cmd $KAFKA_IP "KAFKA" '
    echo "Checking Kafka status..."
    
    # Check if Kafka containers are running
    if ! sudo docker ps | grep kafka > /dev/null; then
        echo "Starting Kafka services..."
        
        # Start Zookeeper
        sudo docker run -d --name zookeeper \
            -p 2181:2181 \
            -e ZOOKEEPER_CLIENT_PORT=2181 \
            -e ZOOKEEPER_TICK_TIME=2000 \
            --memory=300m \
            --restart unless-stopped \
            confluentinc/cp-zookeeper:7.4.0
        
        sleep 20
        
        # Start Kafka
        sudo docker run -d --name kafka \
            -p 9092:9092 \
            -e KAFKA_BROKER_ID=1 \
            -e KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181 \
            -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:9092 \
            -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
            -e KAFKA_AUTO_CREATE_TOPICS_ENABLE=true \
            -e KAFKA_JVM_PERFORMANCE_OPTS="-Xmx400m -Xms400m" \
            -e KAFKA_LOG_RETENTION_HOURS=1 \
            --memory=600m \
            --link zookeeper \
            --restart unless-stopped \
            confluentinc/cp-kafka:7.4.0
        
        sleep 30
        
        # Create topic
        sudo docker exec kafka kafka-topics --create --topic video-stream-1 --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true
    fi
    
    echo "✓ Kafka services running"
    sudo docker ps --format "table {{.Names}}\t{{.Status}}"
    
    # List topics
    echo "Available topics:"
    sudo docker exec kafka kafka-topics --list --bootstrap-server localhost:9092
'

echo ""
echo "STEP 3: Deploy Pipeline Scripts"
echo "==============================="

# Deploy the consumer and extractor with correct configurations
copy_file $KAFKA_IP "KAFKA" "enhanced_extractor.py" "extractor.py"
copy_file $KAFKA_IP "KAFKA" "enhanced_consumer.py" "consumer.py"
copy_file $KAFKA_IP "KAFKA" "videos/demo.mp4" "video.mp4"

run_cmd $KAFKA_IP "KAFKA" '
    chmod +x extractor.py consumer.py
    
    # Install Python dependencies
    pip3 install kafka-python opencv-python-headless boto3 pillow requests --user
    
    echo "✓ Pipeline scripts deployed"
'

echo ""
echo "STEP 4: Test Complete End-to-End Pipeline"
echo "========================================="

echo "Starting consumer..."
run_cmd $KAFKA_IP "KAFKA" 'pkill -f consumer.py || true'
run_cmd $KAFKA_IP "KAFKA" 'nohup python3 consumer.py > consumer.log 2>&1 &'

sleep 5

echo "Testing inference service health..."
run_cmd $K8S_IP "INFERENCE" 'curl -s http://localhost:8080/health | python3 -m json.tool'

sleep 5

echo "Running frame extractor for 60 seconds..."
run_cmd $KAFKA_IP "KAFKA" 'timeout 60 python3 extractor.py --source file --duration 60 > extractor.log 2>&1 &'

sleep 65

echo ""
echo "STEP 5: Check Results"
echo "===================="

echo "Consumer logs (last 20 lines):"
run_cmd $KAFKA_IP "KAFKA" 'tail -20 consumer.log'

echo ""
echo "Extractor logs (last 10 lines):"
run_cmd $KAFKA_IP "KAFKA" 'tail -10 extractor.log'

echo ""
echo "Inference service status:"
run_cmd $K8S_IP "INFERENCE" 'sudo docker ps && curl -s http://localhost:8080/info | python3 -m json.tool'

echo ""
echo "S3 bucket contents:"
echo "Results JSON files:"
aws s3 ls s3://$S3_BUCKET/results/ --region us-east-1 | head -5

echo ""
echo "Annotated frames:"
aws s3 ls s3://$S3_BUCKET/annotated_frames/ --region us-east-1 | head -5

echo ""
echo -e "${GREEN}Complete Pipeline Deployment Finished!${NC}"
echo ""
echo "Pipeline Architecture:"
echo "======================"
echo "📹 RTSP Server (${RTSP_IP}:8554) - Video Source"
echo "⬇️"
echo "📊 Frame Extractor (${KAFKA_IP}) - Extracts 25-frame batches"
echo "⬇️"  
echo "🔄 Kafka (${KAFKA_IP}:9092) - Message Queue"
echo "⬇️"
echo "🧠 Consumer (${KAFKA_IP}) - Processes batches"
echo "⬇️"
echo "🤖 Containerized Inference Service (${K8S_IP}:8080) - Object Detection"
echo "⬇️"
echo "🎯 Post-processing - Draws bounding boxes"
echo "⬇️"
echo "☁️ S3 Upload (${S3_BUCKET}) - Stores annotated frames"
echo ""
echo "✅ Key Features Implemented:"
echo "• Containerized inference service (CPU-based object detection)"
echo "• Consumer calls inference service with 25-frame batches"
echo "• Post-processing draws bounding boxes on frames"
echo "• Annotated frames uploaded to S3 for verification"
echo "• Complete separation: inference in container, post-processing outside"
echo ""
echo "🔍 Verification Commands:"
echo "• Monitor consumer: ssh ec2-user@${KAFKA_IP} 'tail -f consumer.log'"
echo "• Check inference: curl http://${K8S_IP}:8080/health"
echo "• View S3 results: aws s3 ls s3://${S3_BUCKET}/ --recursive"
