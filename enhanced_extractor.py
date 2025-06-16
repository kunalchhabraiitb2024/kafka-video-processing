#!/usr/bin/env python3
"""
OptifYe Enhanced Frame Extractor
Extracts frames from RTSP stream or video file and publishes to Kafka
"""

import cv2
import json
import base64
import time
import argparse
import sys
from kafka import KafkaProducer
from datetime import datetime

class OptifYeExtractor:
    def __init__(self, source_type="file", source_path="video.mp4", rtsp_url=None):
        # Configuration
        self.kafka_topic = "video-stream-1"
        self.kafka_servers = ["10.0.1.37:9092"]
        self.batch_size = 25
        self.frame_width = 320
        self.frame_height = 240
        self.jpeg_quality = 70
        
        # Source configuration
        self.source_type = source_type
        self.source_path = source_path
        self.rtsp_url = rtsp_url or "rtsp://23.20.26.169:8554/video"
        
        # State
        self.batch = []
        self.batch_id = 0
        self.frame_count = 0
        self.total_batches_sent = 0
        
        # Initialize services
        self.setup_kafka()
        self.setup_video_source()
        
        print("OptifYe Frame Extractor initialized successfully")
    
    def setup_kafka(self):
        """Initialize Kafka producer"""
        try:
            self.producer = KafkaProducer(
                bootstrap_servers=self.kafka_servers,
                value_serializer=lambda v: json.dumps(v).encode("utf-8"),
                max_request_size=10485760,  # 10MB
                buffer_memory=33554432,     # 32MB
                batch_size=16384,
                linger_ms=10
            )
            print("✓ Kafka producer connected")
        except Exception as e:
            print(f"✗ Kafka connection failed: {e}")
            sys.exit(1)
    
    def setup_video_source(self):
        """Initialize video capture"""
        try:
            if self.source_type == "rtsp":
                print(f"Connecting to RTSP stream: {self.rtsp_url}")
                self.cap = cv2.VideoCapture(self.rtsp_url)
                # Set buffer size to reduce latency
                self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            else:
                print(f"Opening video file: {self.source_path}")
                self.cap = cv2.VideoCapture(self.source_path)
            
            if not self.cap.isOpened():
                raise Exception("Failed to open video source")
            
            # Get video properties
            fps = self.cap.get(cv2.CAP_PROP_FPS)
            width = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            
            print(f"✓ Video source opened: {width}x{height} @ {fps:.1f} FPS")
            
        except Exception as e:
            print(f"✗ Video source setup failed: {e}")
            sys.exit(1)
    
    def preprocess_frame(self, frame):
        """Preprocess frame for transmission"""
        try:
            # Resize frame
            frame_resized = cv2.resize(frame, (self.frame_width, self.frame_height))
            
            # Encode as JPEG
            encode_params = [cv2.IMWRITE_JPEG_QUALITY, self.jpeg_quality]
            _, buffer = cv2.imencode(".jpg", frame_resized, encode_params)
            
            # Convert to base64
            frame_b64 = base64.b64encode(buffer).decode("utf-8")
            
            return frame_b64
            
        except Exception as e:
            print(f"Frame preprocessing error: {e}")
            return None
    
    def send_batch(self):
        """Send current batch to Kafka"""
        if not self.batch:
            return
        
        try:
            self.batch_id += 1
            timestamp = datetime.now().isoformat()
            
            message = {
                "batch_id": self.batch_id,
                "frame_count": len(self.batch),
                "frames": self.batch,
                "timestamp": timestamp,
                "source_type": self.source_type,
                "extractor_info": {
                    "frame_width": self.frame_width,
                    "frame_height": self.frame_height,
                    "jpeg_quality": self.jpeg_quality
                }
            }
            
            # Send to Kafka
            future = self.producer.send(self.kafka_topic, message)
            self.producer.flush()
            
            self.total_batches_sent += 1
            print(f"✓ Sent batch {self.batch_id} ({len(self.batch)} frames) - Total batches: {self.total_batches_sent}")
            
            # Clear batch
            self.batch = []
            
        except Exception as e:
            print(f"✗ Failed to send batch {self.batch_id}: {e}")
    
    def extract_from_file(self, duration_seconds=None):
        """Extract frames from video file"""
        print(f"Starting frame extraction from file...")
        if duration_seconds:
            print(f"Running for {duration_seconds} seconds")
        
        start_time = time.time()
        
        try:
            while True:
                ret, frame = self.cap.read()
                
                if not ret:
                    if self.source_type == "file":
                        # Loop the video file
                        self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                        continue
                    else:
                        print("End of stream reached")
                        break
                
                # Preprocess frame
                frame_b64 = self.preprocess_frame(frame)
                if not frame_b64:
                    continue
                
                # Add to batch
                self.batch.append({
                    "frame_id": self.frame_count,
                    "data": frame_b64,
                    "timestamp": time.time()
                })
                
                self.frame_count += 1
                
                # Send batch when full
                if len(self.batch) >= self.batch_size:
                    self.send_batch()
                
                # Check duration limit
                if duration_seconds and (time.time() - start_time) >= duration_seconds:
                    print(f"Duration limit reached ({duration_seconds}s)")
                    break
                
                # Add small delay for file processing
                if self.source_type == "file":
                    time.sleep(0.1)  # 10 FPS processing
                    
        except KeyboardInterrupt:
            print("\nStopping extraction...")
        
        # Send remaining frames
        if self.batch:
            self.send_batch()
        
        print(f"Extraction complete: {self.frame_count} frames, {self.total_batches_sent} batches")
    
    def extract_from_rtsp(self, duration_seconds=None):
        """Extract frames from RTSP stream"""
        print(f"Starting frame extraction from RTSP...")
        if duration_seconds:
            print(f"Running for {duration_seconds} seconds")
        
        start_time = time.time()
        last_frame_time = time.time()
        
        try:
            while True:
                ret, frame = self.cap.read()
                
                if not ret:
                    print("Failed to read frame from RTSP, retrying...")
                    time.sleep(1)
                    continue
                
                current_time = time.time()
                
                # Skip frames if coming too fast (throttle to ~5 FPS)
                if current_time - last_frame_time < 0.2:
                    continue
                
                last_frame_time = current_time
                
                # Preprocess frame
                frame_b64 = self.preprocess_frame(frame)
                if not frame_b64:
                    continue
                
                # Add to batch
                self.batch.append({
                    "frame_id": self.frame_count,
                    "data": frame_b64,
                    "timestamp": current_time
                })
                
                self.frame_count += 1
                
                # Send batch when full
                if len(self.batch) >= self.batch_size:
                    self.send_batch()
                
                # Check duration limit
                if duration_seconds and (current_time - start_time) >= duration_seconds:
                    print(f"Duration limit reached ({duration_seconds}s)")
                    break
                    
        except KeyboardInterrupt:
            print("\nStopping extraction...")
        
        # Send remaining frames
        if self.batch:
            self.send_batch()
        
        print(f"Extraction complete: {self.frame_count} frames, {self.total_batches_sent} batches")
    
    def run(self, duration_seconds=None):
        """Main extraction loop"""
        try:
            if self.source_type == "rtsp":
                self.extract_from_rtsp(duration_seconds)
            else:
                self.extract_from_file(duration_seconds)
        
        finally:
            self.cap.release()
            self.producer.close()
            print("Frame extractor stopped")

def main():
    parser = argparse.ArgumentParser(description="OptifYe Frame Extractor")
    parser.add_argument("--source", choices=["file", "rtsp"], default="file",
                       help="Source type: file or rtsp")
    parser.add_argument("--file", default="video.mp4",
                       help="Video file path (for file source)")
    parser.add_argument("--rtsp", default="rtsp://23.20.26.169:8554/video",
                       help="RTSP URL (for rtsp source)")
    parser.add_argument("--duration", type=int,
                       help="Duration in seconds (default: unlimited)")
    
    args = parser.parse_args()
    
    extractor = OptifYeExtractor(
        source_type=args.source,
        source_path=args.file,
        rtsp_url=args.rtsp
    )
    
    extractor.run(args.duration)

if __name__ == "__main__":
    main()
