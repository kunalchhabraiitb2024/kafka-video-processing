#!/bin/bash
# OptifYe Clean Pipeline Deployment
# RTSP → Kafka → Inference → S3

set -e

# Colors for output
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

echo -e "${BLUE}OptifYe Pipeline Deployment${NC}"
echo -e "${BLUE}===========================${NC}"
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

echo "STEP 1: Get proper demo video"
echo "=============================="

# Download a small working video
if [ ! -f "videos/demo.mp4" ]; then
    echo "Downloading demo video..."
    mkdir -p videos
    # Download a small test video (Big Buck Bunny sample)
    curl -L "https://sample-videos.com/zip/10/mp4/480/SampleVideo_480x360_1mb.mp4" -o videos/demo.mp4
    echo "Demo video downloaded: $(ls -lh videos/demo.mp4)"
fi

echo ""
echo "STEP 2: Deploy Video to RTSP Server"
echo "===================================="

copy_file $RTSP_IP "RTSP" "videos/demo.mp4" "demo.mp4"

run_cmd $RTSP_IP "RTSP" '
    # Clean up
    sudo docker stop $(sudo docker ps -aq) || true
    sudo docker rm $(sudo docker ps -aq) || true
    
    # Start RTSP server
    sudo docker run -d --name rtsp-server \
        -p 8554:8554 \
        -v ~/demo.mp4:/media/video.mp4 \
        bluenviron/mediamtx
    
    sleep 5
    echo "RTSP Server Status:"
    sudo docker ps
'

echo ""
echo "STEP 3: Setup Kafka"
echo "==================="

run_cmd $KAFKA_IP "KAFKA" '
    # Clean up
    sudo docker stop $(sudo docker ps -aq) || true
    sudo docker rm $(sudo docker ps -aq) || true
    
    # Start Zookeeper
    sudo docker run -d --name zookeeper \
        -p 2181:2181 \
        -e ZOOKEEPER_CLIENT_PORT=2181 \
        -e ZOOKEEPER_TICK_TIME=2000 \
        --memory=256m \
        confluentinc/cp-zookeeper:7.4.0
    
    sleep 15
    
    # Start Kafka
    sudo docker run -d --name kafka \
        -p 9092:9092 \
        -e KAFKA_BROKER_ID=1 \
        -e KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181 \
        -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:9092 \
        -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
        -e KAFKA_AUTO_CREATE_TOPICS_ENABLE=true \
        -e KAFKA_JVM_PERFORMANCE_OPTS="-Xmx256m -Xms256m" \
        --memory=512m \
        --link zookeeper \
        confluentinc/cp-kafka:7.4.0
    
    sleep 20
    
    # Create topic
    sudo docker exec kafka kafka-topics --create --topic video-stream-1 --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1 || true
    
    echo "Kafka Status:"
    sudo docker ps
'

echo ""
echo "STEP 4: Deploy Inference Service"
echo "================================="

run_cmd $K8S_IP "K8S" '
    # Clean up
    sudo docker stop $(sudo docker ps -aq) || true
    sudo docker rm $(sudo docker ps -aq) || true
    
    # Create inference service
    cat > inference.py << "EOF"
from flask import Flask, request, jsonify
import time

app = Flask(__name__)

@app.route("/health")
def health():
    return jsonify({"status": "healthy"})

@app.route("/infer", methods=["POST"])
def infer():
    data = request.json
    batch_id = data.get("batch_id")
    frames = data.get("frames", [])
    
    print(f"Processing batch {batch_id} with {len(frames)} frames")
    
    # Mock detections
    results = []
    for frame in frames:
        results.append({
            "frame_id": frame["frame_id"],
            "detections": [
                {"class": "person", "confidence": 0.85, "bbox": [50, 50, 150, 200]},
                {"class": "car", "confidence": 0.72, "bbox": [200, 100, 300, 180]}
            ]
        })
    
    response = {
        "batch_id": batch_id,
        "frame_count": len(frames),
        "results": results,
        "inference_time": 0.1,
        "status": "success"
    }
    
    return jsonify(response)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

    # Create Dockerfile
    cat > Dockerfile << "EOF"
FROM python:3.9-slim
WORKDIR /app
RUN pip install flask
COPY inference.py /app/
EXPOSE 8080
CMD ["python", "inference.py"]
EOF

    # Build and run
    sudo docker build -t inference .
    sudo docker run -d --name inference -p 8080:8080 inference
    
    sleep 10
    echo "Inference Service Status:"
    sudo docker ps
    curl -s http://localhost:8080/health
'

echo ""
echo "STEP 5: Create Pipeline Scripts"
echo "==============================="

run_cmd $KAFKA_IP "KAFKA" '
    # Copy video locally for processing
    cp ~/demo.mp4 ~/video.mp4 || echo "Video already exists"
    
    # Create frame extractor
    cat > extractor.py << "EOF"
import cv2
import json
import base64
import time
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers=["localhost:9092"],
    value_serializer=lambda v: json.dumps(v).encode("utf-8")
)

cap = cv2.VideoCapture("video.mp4")
batch = []
batch_id = 0
frame_count = 0

print("Starting frame extraction...")

while True:
    ret, frame = cap.read()
    if not ret:
        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
        continue
    
    # Resize and encode
    frame = cv2.resize(frame, (320, 240))
    _, buffer = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
    frame_b64 = base64.b64encode(buffer).decode("utf-8")
    
    batch.append({
        "frame_id": frame_count,
        "data": frame_b64
    })
    
    frame_count += 1
    
    if len(batch) == 25:
        batch_id += 1
        message = {
            "batch_id": batch_id,
            "frame_count": 25,
            "frames": batch
        }
        
        producer.send("video-stream-1", message)
        producer.flush()
        print(f"Sent batch {batch_id}")
        
        batch = []
        time.sleep(2)
EOF

    # Create consumer
    cat > consumer.py << "EOF"
import json
import requests
import boto3
from datetime import datetime
from kafka import KafkaConsumer

consumer = KafkaConsumer(
    "video-stream-1",
    bootstrap_servers=["localhost:9092"],
    value_deserializer=lambda m: json.loads(m.decode("utf-8")),
    group_id="processor"
)

try:
    s3 = boto3.client("s3", region_name="us-east-1")
    print("Connected to S3")
except:
    s3 = None
    print("S3 connection failed")

print("Starting consumer...")

for message in consumer:
    batch_data = message.value
    batch_id = batch_data["batch_id"]
    
    print(f"Processing batch {batch_id}")
    
    # Call inference
    try:
        response = requests.post(
            "http://54.80.24.67:8080/infer",
            json=batch_data,
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            print(f"Inference complete for batch {batch_id}")
            
            # Upload to S3
            if s3:
                key = f"results/batch_{batch_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
                try:
                    s3.put_object(
                        Bucket="optifye-video-pipeline-output-9efa2ef2",
                        Key=key,
                        Body=json.dumps(result, indent=2)
                    )
                    print(f"Uploaded to S3: {key}")
                except Exception as e:
                    print(f"S3 upload failed: {e}")
        
    except Exception as e:
        print(f"Inference failed: {e}")
EOF

    echo "Pipeline scripts created"
'

echo ""
echo "STEP 6: Test Pipeline"
echo "===================="

echo "Starting consumer..."
run_cmd $KAFKA_IP "KAFKA" 'nohup python3 consumer.py > consumer.log 2>&1 &'

sleep 3

echo "Running frame extractor for 30 seconds..."
run_cmd $KAFKA_IP "KAFKA" 'timeout 30s python3 extractor.py || echo "Extractor test complete"'

sleep 5

echo "Checking results..."
run_cmd $KAFKA_IP "KAFKA" 'tail -10 consumer.log'

echo ""
echo "Pipeline Status:"
echo "================"

echo "RTSP Server:"
run_cmd $RTSP_IP "RTSP" 'sudo docker ps --format "table {{.Names}}\t{{.Status}}"'

echo ""
echo "Kafka:"
run_cmd $KAFKA_IP "KAFKA" 'sudo docker ps --format "table {{.Names}}\t{{.Status}}"'

echo ""
echo "Inference Service:"
run_cmd $K8S_IP "K8S" 'sudo docker ps --format "table {{.Names}}\t{{.Status}}" && echo "" && curl -s http://localhost:8080/health'

echo ""
echo "Pipeline Deployment Complete!"
echo "Manual testing:"
echo "1. ssh ec2-user@${KAFKA_IP} 'python3 extractor.py'"
echo "2. ssh ec2-user@${KAFKA_IP} 'python3 consumer.py'"
echo "3. Check S3 bucket: ${S3_BUCKET}"
