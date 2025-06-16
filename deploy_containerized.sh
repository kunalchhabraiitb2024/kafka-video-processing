#!/bin/bash
# OptifYe Complete Pipeline Deployment with Containerized Inference
# RTSP → Kafka → Consumer → Kubernetes Inference Service → S3

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

echo -e "${BLUE}OptifYe Containerized Pipeline Deployment${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "RTSP Server: ${RTSP_IP}"
echo -e "Kafka Server: ${KAFKA_IP}" 
echo -e "K8s Node: ${K8S_IP}"
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

echo "STEP 1: Deploy Containerized Inference Service to K8s"
echo "====================================================="

# Copy all inference service files
copy_file $K8S_IP "K8S" "inference_service.py" "inference_service.py"
copy_file $K8S_IP "K8S" "Dockerfile" "Dockerfile"
copy_file $K8S_IP "K8S" "requirements_inference.txt" "requirements_inference.txt"
copy_file $K8S_IP "K8S" "k8s-deployment.yaml" "k8s-deployment.yaml"

run_cmd $K8S_IP "K8S" '
    echo "Setting up Kubernetes environment..."
    
    # Install Docker
    sudo yum update -y
    sudo yum install -y docker
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ec2-user
    
    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    
    # Install minikube for single-node K8s
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    
    # Start minikube with appropriate resources
    minikube start --driver=docker --cpus=1 --memory=1024mb --disk-size=10gb
    
    echo "Building inference service container..."
    docker build -t inference:latest .
    
    # Load image into minikube
    minikube image load inference:latest
    
    echo "Deploying to Kubernetes..."
    kubectl apply -f k8s-deployment.yaml
    
    # Wait for deployment
    echo "Waiting for deployment to be ready..."
    kubectl wait --for=condition=ready pod -l app=inference-service --timeout=180s
    
    # Start port-forward in background
    nohup kubectl port-forward service/inference-service 8080:8080 > /dev/null 2>&1 &
    
    sleep 10
    
    echo "✓ Kubernetes deployment completed"
    kubectl get pods
    kubectl get services
    
    # Test the service
    echo "Testing inference service..."
    curl -f http://localhost:8080/health || echo "Service not ready yet"
'

echo ""
echo "STEP 2: Deploy Enhanced Pipeline"
echo "==============================="

# Deploy the consumer and extractor
copy_file $KAFKA_IP "KAFKA" "enhanced_extractor.py" "extractor.py"
copy_file $KAFKA_IP "KAFKA" "enhanced_consumer.py" "consumer.py"
copy_file $KAFKA_IP "KAFKA" "videos/demo.mp4" "video.mp4"

echo ""
echo "STEP 3: Test End-to-End Pipeline"
echo "==============================="

echo "Starting consumer..."
run_cmd $KAFKA_IP "KAFKA" 'pkill -f consumer.py || true'
run_cmd $KAFKA_IP "KAFKA" 'nohup python3 consumer.py > consumer.log 2>&1 &'

sleep 5

echo "Testing inference service health..."
run_cmd $K8S_IP "K8S" 'curl -s http://localhost:8080/health | python3 -m json.tool'

sleep 5

echo "Running frame extractor..."
run_cmd $KAFKA_IP "KAFKA" 'python3 extractor.py --source file --duration 30 > extractor.log 2>&1 &'

sleep 30

echo ""
echo "STEP 4: Check Results"
echo "===================="

echo "Consumer logs:"
run_cmd $KAFKA_IP "KAFKA" 'tail -15 consumer.log'

echo ""
echo "Extractor logs:"
run_cmd $KAFKA_IP "KAFKA" 'tail -10 extractor.log'

echo ""
echo "Kubernetes status:"
run_cmd $K8S_IP "K8S" 'kubectl get pods && kubectl get services'

echo ""
echo "Inference service stats:"
run_cmd $K8S_IP "K8S" 'curl -s http://localhost:8080/info | python3 -m json.tool'

echo ""
echo "S3 bucket contents:"
aws s3 ls s3://$S3_BUCKET/ --recursive | head -10

echo ""
echo -e "${GREEN}Containerized Pipeline Deployment Complete!${NC}"
echo ""
echo "Architecture:"
echo "============"
echo "📹 RTSP Server (${RTSP_IP}:8554)"
echo "⬇️"
echo "📊 Frame Extractor → Kafka (${KAFKA_IP}:9092)"
echo "⬇️"  
echo "🔄 Consumer → Kubernetes Inference Service (${K8S_IP}:8080)"
echo "⬇️"
echo "🎯 Post-processing → S3 Bucket (${S3_BUCKET})"
echo ""
echo "Key Features:"
echo "• ✅ Containerized inference service in Kubernetes"
echo "• ✅ CPU-based object detection"
echo "• ✅ Consumer calls containerized inference API"
echo "• ✅ Post-processing with bounding box annotations"
echo "• ✅ Annotated frames uploaded to S3"
