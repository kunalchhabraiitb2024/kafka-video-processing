#!/bin/bash
# K8s Node Setup for OptifYe Pipeline

# Update system
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install minikube for single-node cluster
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube
mv minikube /usr/local/bin/

# Start minikube
su - ec2-user -c "minikube start --driver=docker --memory=1024 --cpus=1"

# Install dependencies
yum install -y python3 python3-pip
pip3 install flask opencv-python-headless

# Create inference service
cat > /home/ec2-user/inference.py << 'EOF'
from flask import Flask, request, jsonify
import time
import base64
import io
from PIL import Image
import json

app = Flask(__name__)

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "service": "inference-api"})

@app.route("/infer", methods=["POST"])
def infer():
    try:
        data = request.json
        batch_id = data.get("batch_id")
        frames = data.get("frames", [])
        
        print(f"Processing batch {batch_id} with {len(frames)} frames")
        
        # Mock object detection results
        results = []
        for i, frame in enumerate(frames):
            frame_id = frame.get("frame_id", i)
            
            # Simulate different detection scenarios
            detections = []
            if i % 3 == 0:  # Person detection
                detections.append({
                    "class": "person",
                    "confidence": 0.85 + (i * 0.01) % 0.15,
                    "bbox": [50 + i*5, 50 + i*3, 150 + i*2, 200 + i*4]
                })
            if i % 5 == 0:  # Car detection
                detections.append({
                    "class": "car", 
                    "confidence": 0.72 + (i * 0.02) % 0.28,
                    "bbox": [200 + i*3, 100 + i*2, 300 + i*4, 180 + i*3]
                })
            if i % 7 == 0:  # Bicycle detection
                detections.append({
                    "class": "bicycle",
                    "confidence": 0.68 + (i * 0.015) % 0.22,
                    "bbox": [120 + i*2, 80 + i*3, 180 + i*2, 140 + i*4]
                })
            
            results.append({
                "frame_id": frame_id,
                "detections": detections,
                "processing_time": 0.05 + (i * 0.001)
            })
        
        response = {
            "batch_id": batch_id,
            "frame_count": len(frames),
            "results": results,
            "total_detections": sum(len(r["detections"]) for r in results),
            "inference_time": 0.1 + len(frames) * 0.005,
            "status": "success",
            "timestamp": time.time()
        }
        
        return jsonify(response)
        
    except Exception as e:
        print(f"Inference error: {e}")
        return jsonify({
            "status": "error",
            "message": str(e),
            "batch_id": data.get("batch_id") if 'data' in locals() else None
        }), 500

if __name__ == "__main__":
    print("Starting OptifYe Inference Service...")
    app.run(host="0.0.0.0", port=8080, debug=False)
EOF

# Create Dockerfile
cat > /home/ec2-user/Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

RUN pip install flask pillow

COPY inference.py /app/

EXPOSE 8080

CMD ["python", "inference.py"]
EOF

# Set ownership
chown -R ec2-user:ec2-user /home/ec2-user/

# Build and deploy with Docker (fallback)
su - ec2-user -c "
    cd /home/ec2-user
    docker build -t inference:latest .
    docker run -d --name inference -p 8080:8080 --restart unless-stopped inference:latest
"

# Setup K8s deployment (if minikube is working)
su - ec2-user -c "
    # Check if minikube is running
    if minikube status | grep -q 'Running'; then
        echo 'Setting up K8s deployment...'
        
        # Load Docker image into minikube
        minikube image load inference:latest
        
        # Create deployment
        kubectl create deployment inference-service --image=inference:latest --port=8080
        kubectl expose deployment inference-service --type=NodePort --port=8080
        
        # Scale if needed
        kubectl scale deployment inference-service --replicas=1
        
        echo 'K8s deployment complete'
    else
        echo 'Using Docker container deployment'
    fi
"

echo "K8s node setup complete"