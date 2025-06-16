#!/bin/bash

# OptifYe Pipeline End-to-End Test
# Final connectivity test and verification

set -e

# Get IP addresses from Terraform
KAFKA_IP="54.89.113.227"
K8S_IP="52.201.251.231"
RTSP_IP="23.20.26.169"
S3_BUCKET="optifye-video-output-o35wbr8c"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}  OptifYe Pipeline Final Test${NC}"
echo -e "${GREEN}======================================${NC}"

# Function to run command on remote server
run_cmd() {
    local ip=$1
    local name=$2
    local cmd=$3
    echo -e "${YELLOW}[$name] $cmd${NC}"
    ssh -i ~/.ssh/optifye-key.pem -o StrictHostKeyChecking=no ec2-user@$ip "$cmd"
}

# Function to copy file to remote server
copy_file() {
    local ip=$1
    local name=$2
    local local_file=$3
    local remote_file=$4
    echo -e "${YELLOW}[$name] Copying $local_file -> $remote_file${NC}"
    scp -i ~/.ssh/optifye-key.pem -o StrictHostKeyChecking=no "$local_file" ec2-user@$ip:"$remote_file"
}

echo ""
echo "STEP 1: Verify Infrastructure Status"
echo "===================================="

echo "Checking RTSP server..."
run_cmd $RTSP_IP "RTSP" 'sudo docker ps --format "table {{.Names}}\t{{.Status}}"'

echo ""
echo "Checking Kafka server..."
run_cmd $KAFKA_IP "KAFKA" 'sudo docker ps --format "table {{.Names}}\t{{.Status}}"'

echo ""
echo "Checking Kafka topics..."
run_cmd $KAFKA_IP "KAFKA" 'sudo docker exec kafka kafka-topics --list --bootstrap-server localhost:9092'

echo ""
echo "Checking inference service..."
run_cmd $K8S_IP "INFERENCE" 'sudo docker ps --format "table {{.Names}}\t{{.Status}}"'

echo ""
echo "Testing inference service health..."
run_cmd $K8S_IP "INFERENCE" 'curl -s http://localhost:8080/health | python3 -m json.tool'

echo ""
echo "STEP 2: Deploy Updated Pipeline Scripts"
echo "======================================="

# Copy updated scripts
copy_file $KAFKA_IP "KAFKA" "enhanced_extractor.py" "extractor.py"
copy_file $KAFKA_IP "KAFKA" "enhanced_consumer.py" "consumer.py"
copy_file $KAFKA_IP "KAFKA" "videos/demo.mp4" "video.mp4"

echo ""
echo "Installing Python dependencies..."
run_cmd $KAFKA_IP "KAFKA" 'pip3 install kafka-python opencv-python-headless boto3 pillow requests --user'

echo ""
echo "STEP 3: Test Kafka Connectivity"
echo "==============================="

echo "Testing Kafka connectivity from consumer..."
run_cmd $KAFKA_IP "KAFKA" 'python3 -c "
from kafka import KafkaConsumer
try:
    consumer = KafkaConsumer(bootstrap_servers=[\"10.0.1.37:9092\"], consumer_timeout_ms=5000)
    print(\"✓ Kafka connection successful\")
    consumer.close()
except Exception as e:
    print(f\"✗ Kafka connection failed: {e}\")
"'

echo ""
echo "STEP 4: Test Inference Service Connectivity"
echo "============================================"

echo "Testing inference service from Kafka instance..."
run_cmd $KAFKA_IP "KAFKA" 'curl -s -m 10 http://10.0.1.170:8080/health | python3 -m json.tool || echo "Inference service not reachable"'

echo ""
echo "STEP 5: Run End-to-End Pipeline Test"
echo "===================================="

echo "Starting consumer in background..."
run_cmd $KAFKA_IP "KAFKA" 'pkill -f consumer.py || true'
run_cmd $KAFKA_IP "KAFKA" 'nohup python3 consumer.py > consumer.log 2>&1 &'

sleep 10

echo "Testing consumer startup..."
run_cmd $KAFKA_IP "KAFKA" 'tail -5 consumer.log'

echo ""
echo "Running frame extractor for 30 seconds..."
run_cmd $KAFKA_IP "KAFKA" 'timeout 30 python3 extractor.py --source file --duration 30 > extractor.log 2>&1 || echo "Extractor completed"'

sleep 35

echo ""
echo "STEP 6: Check Results"
echo "===================="

echo "Consumer logs (last 20 lines):"
run_cmd $KAFKA_IP "KAFKA" 'tail -20 consumer.log'

echo ""
echo "Extractor logs (last 10 lines):"
run_cmd $KAFKA_IP "KAFKA" 'tail -10 extractor.log'

echo ""
echo "Inference service status and stats:"
run_cmd $K8S_IP "INFERENCE" 'curl -s http://localhost:8080/info | python3 -m json.tool'

echo ""
echo "STEP 7: Verify S3 Results"
echo "========================="

echo "Checking S3 bucket contents..."
aws s3 ls s3://$S3_BUCKET/results/ --region us-east-1 2>/dev/null | head -10 || echo "No results yet or S3 not accessible"

echo ""
echo "Total files in S3 bucket:"
aws s3 ls s3://$S3_BUCKET/results/ --region us-east-1 --recursive | wc -l || echo "0"

echo ""
echo "STEP 8: Test Summary"
echo "==================="

echo "Testing RTSP stream access..."
timeout 10 curl -s rtsp://$RTSP_IP:8554/video > /dev/null && echo "✓ RTSP stream accessible" || echo "✗ RTSP stream not accessible"

echo ""
echo "Infrastructure Status:"
echo "  RTSP Server: $RTSP_IP:8554"
echo "  Kafka Server: $KAFKA_IP (internal: 10.0.1.37:9092)"
echo "  Inference Service: $K8S_IP (internal: 10.0.1.170:8080)"
echo "  S3 Bucket: $S3_BUCKET"

echo ""
echo -e "${GREEN}Pipeline test completed!${NC}"
echo -e "${YELLOW}Check the logs above for any errors or issues.${NC}"
