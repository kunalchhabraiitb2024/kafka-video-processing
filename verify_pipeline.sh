#!/bin/bash
# OptifYe End-to-End Pipeline Verification
# Tests: RTSP → Kafka → Inference → S3 flow

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
RTSP_IP="54.172.95.48"
KAFKA_IP="34.207.77.179" 
K8S_IP="54.80.24.67"
S3_BUCKET="optifye-video-pipeline-output-9efa2ef2"
SSH_OPTS="-i ~/.ssh/optifye-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"

echo -e "${BLUE}OptifYe Pipeline End-to-End Verification${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Function to run command on instance
run_cmd() {
    local ip=$1
    local name=$2
    local command=$3
    echo -e "${YELLOW}[${name}]${NC} ${command}"
    ssh $SSH_OPTS ec2-user@$ip "$command"
}

# Function to check service health
check_service() {
    local ip=$1
    local name=$2
    local port=$3
    local endpoint=$4
    
    echo -e "${YELLOW}Checking ${name} health...${NC}"
    if run_cmd $ip $name "curl -f -s http://localhost:${port}${endpoint} > /dev/null"; then
        echo -e "${GREEN}✓ ${name} is healthy${NC}"
        return 0
    else
        echo -e "${RED}✗ ${name} is not responding${NC}"
        return 1
    fi
}

echo "STEP 1: Infrastructure Health Check"
echo "===================================="

# Check RTSP Server
echo -e "${YELLOW}Checking RTSP Server...${NC}"
if run_cmd $RTSP_IP "RTSP" "sudo docker ps | grep rtsp-server"; then
    echo -e "${GREEN}✓ RTSP Server is running${NC}"
else
    echo -e "${RED}✗ RTSP Server is not running${NC}"
fi

# Check Kafka
echo -e "${YELLOW}Checking Kafka...${NC}"
if run_cmd $KAFKA_IP "KAFKA" "sudo docker ps | grep kafka"; then
    echo -e "${GREEN}✓ Kafka is running${NC}"
    
    # Check topic exists
    if run_cmd $KAFKA_IP "KAFKA" "sudo docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 | grep video-stream-1"; then
        echo -e "${GREEN}✓ Topic 'video-stream-1' exists${NC}"
    else
        echo -e "${RED}✗ Topic 'video-stream-1' not found${NC}"
    fi
else
    echo -e "${RED}✗ Kafka is not running${NC}"
fi

# Check Inference Service
check_service $K8S_IP "Inference" 8080 "/health"

echo ""
echo "STEP 2: End-to-End Pipeline Test"
echo "================================="

# Start consumer in background
echo -e "${YELLOW}Starting consumer...${NC}"
run_cmd $KAFKA_IP "KAFKA" "pkill -f consumer.py || true"
run_cmd $KAFKA_IP "KAFKA" "nohup python3 consumer.py > consumer_test.log 2>&1 &"

sleep 5

# Run frame extractor for a short test
echo -e "${YELLOW}Running frame extractor (30 seconds)...${NC}"
run_cmd $KAFKA_IP "KAFKA" "timeout 30s python3 extractor.py > extractor_test.log 2>&1 || echo 'Extractor test completed'"

sleep 10

echo ""
echo "STEP 3: Results Verification"
echo "============================"

# Check consumer logs
echo -e "${YELLOW}Consumer logs:${NC}"
run_cmd $KAFKA_IP "KAFKA" "tail -20 consumer_test.log"

# Check S3 uploads
echo ""
echo -e "${YELLOW}Checking S3 bucket for results...${NC}"
if aws s3 ls s3://$S3_BUCKET/results/ --region us-east-1 2>/dev/null; then
    echo -e "${GREEN}✓ Results found in S3 bucket${NC}"
    echo -e "${YELLOW}Latest files:${NC}"
    aws s3 ls s3://$S3_BUCKET/results/ --region us-east-1 --recursive | tail -5
else
    echo -e "${RED}✗ No results found in S3 or S3 access failed${NC}"
fi

echo ""
echo "STEP 4: Performance Metrics"
echo "==========================="

# Check Kafka message count
echo -e "${YELLOW}Kafka topic message count:${NC}"
run_cmd $KAFKA_IP "KAFKA" "sudo docker exec kafka kafka-run-class kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic video-stream-1 --time -1"

# Check inference service stats
echo -e "${YELLOW}Inference service logs:${NC}"
run_cmd $K8S_IP "K8S" "sudo docker logs inference --tail 10"

echo ""
echo "STEP 5: Clean Pipeline Test"
echo "==========================="

# Kill all background processes
echo -e "${YELLOW}Stopping test processes...${NC}"
run_cmd $KAFKA_IP "KAFKA" "pkill -f consumer.py || true"
run_cmd $KAFKA_IP "KAFKA" "pkill -f extractor.py || true"

echo ""
echo -e "${GREEN}Pipeline Verification Complete!${NC}"
echo ""
echo "Manual Commands for Further Testing:"
echo "====================================="
echo "1. Run producer: ssh ec2-user@${KAFKA_IP} 'python3 extractor.py'"
echo "2. Run consumer: ssh ec2-user@${KAFKA_IP} 'python3 consumer.py'"
echo "3. Check inference: curl http://${K8S_IP}:8080/health"
echo "4. View S3 results: aws s3 ls s3://${S3_BUCKET}/results/ --recursive"
echo ""
echo "Pipeline Status Summary:"
echo "========================"
echo "• RTSP Server: ${RTSP_IP}:8554"
echo "• Kafka Broker: ${KAFKA_IP}:9092"
echo "• Inference API: ${K8S_IP}:8080"
echo "• S3 Bucket: ${S3_BUCKET}"
