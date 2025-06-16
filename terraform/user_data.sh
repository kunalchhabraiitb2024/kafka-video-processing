#!/bin/bash
yum update -y
yum install -y docker

# Start Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install AWS CLI
yum install -y aws-cli

# Create sample video directory
mkdir -p /home/ec2-user/videos
cd /home/ec2-user/videos

# Download a sample video (or create a simple test pattern)
cat > create_test_video.py << 'EOF'
import cv2
import numpy as np

# Create a simple test video with moving rectangle
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('test_video.mp4', fourcc, 30.0, (640, 480))

for i in range(900):  # 30 seconds at 30fps
    # Create a frame with moving rectangle
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    
    # Moving rectangle
    x = (i * 2) % 600
    y = (i) % 400
    
    cv2.rectangle(frame, (x, y), (x+40, y+40), (0, 255, 0), -1)
    cv2.putText(frame, f'Frame {i}', (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
    
    out.write(frame)

out.release()
print("Test video created: test_video.mp4")
EOF

# Install Python and create video
amazon-linux-extras install python3.8 -y
pip3 install opencv-python
python3 create_test_video.py

# Start RTSP server with Docker
docker run -d --restart=unless-stopped \
  --name rtsp-server \
  -p 8554:8554 \
  -v /home/ec2-user/videos/test_video.mp4:/media/video.mp4:ro \
  aler9/rtsp-simple-server

# Create a simple health check endpoint
cat > /home/ec2-user/health_check.py << 'EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {"status": "healthy", "rtsp_url": "rtsp://localhost:8554/video.mp4"}
            self.wfile.write(json.dumps(response).encode())

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 80), HealthHandler)
    server.serve_forever()
EOF

# Start health check server
nohup python3 /home/ec2-user/health_check.py &

echo "RTSP server setup complete"
