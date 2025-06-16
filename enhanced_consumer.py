#!/usr/bin/env python3
"""
OptifYe Enhanced Consumer
Processes Kafka messages, calls inference service, and uploads annotated results to S3
"""

import json
import requests
import boto3
import base64
import cv2
import numpy as np
from datetime import datetime
from kafka import KafkaConsumer
import time
import io
from PIL import Image, ImageDraw, ImageFont
import sys

class OptifYeConsumer:
    def __init__(self):
        # Configuration
        self.kafka_topic = "video-stream-1"
        self.kafka_servers = ["localhost:9092"]
        self.inference_url = "http://54.80.24.67:8080/infer"
        self.s3_bucket = "optifye-video-pipeline-output-9efa2ef2"
        self.s3_region = "us-east-1"
        
        # Initialize services
        self.setup_kafka()
        self.setup_s3()
        
        print("OptifYe Consumer initialized successfully")
    
    def setup_kafka(self):
        """Initialize Kafka consumer"""
        try:
            self.consumer = KafkaConsumer(
                self.kafka_topic,
                bootstrap_servers=self.kafka_servers,
                value_deserializer=lambda m: json.loads(m.decode("utf-8")),
                group_id="optifye-processor",
                auto_offset_reset='latest',
                consumer_timeout_ms=10000
            )
            print("✓ Kafka consumer connected")
        except Exception as e:
            print(f"✗ Kafka connection failed: {e}")
            sys.exit(1)
    
    def setup_s3(self):
        """Initialize S3 client"""
        try:
            self.s3_client = boto3.client("s3", region_name=self.s3_region)
            # Test connection
            self.s3_client.head_bucket(Bucket=self.s3_bucket)
            print("✓ S3 client connected")
        except Exception as e:
            print(f"✗ S3 connection failed: {e}")
            self.s3_client = None
    
    def call_inference(self, batch_data):
        """Call inference service"""
        try:
            response = requests.post(
                self.inference_url,
                json=batch_data,
                timeout=30,
                headers={"Content-Type": "application/json"}
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                print(f"Inference API error: {response.status_code}")
                return None
                
        except requests.exceptions.RequestException as e:
            print(f"Inference request failed: {e}")
            return None
    
    def draw_annotations(self, frame_data, detections):
        """Draw bounding boxes on frame"""
        try:
            # Decode base64 image
            img_data = base64.b64decode(frame_data)
            img = Image.open(io.BytesIO(img_data))
            draw = ImageDraw.Draw(img)
            
            # Draw bounding boxes
            for detection in detections:
                bbox = detection["bbox"]
                class_name = detection["class"]
                confidence = detection["confidence"]
                
                # Draw rectangle
                draw.rectangle(bbox, outline="red", width=2)
                
                # Draw label
                label = f"{class_name}: {confidence:.2f}"
                draw.text((bbox[0], bbox[1] - 15), label, fill="red")
            
            # Convert back to base64
            buffer = io.BytesIO()
            img.save(buffer, format="JPEG")
            return base64.b64encode(buffer.getvalue()).decode("utf-8")
            
        except Exception as e:
            print(f"Annotation error: {e}")
            return frame_data  # Return original if annotation fails
    
    def post_process_results(self, batch_data, inference_results):
        """Post-process inference results with annotations"""
        try:
            processed_results = inference_results.copy()
            processed_frames = []
            
            for i, result in enumerate(inference_results["results"]):
                frame_id = result["frame_id"]
                detections = result["detections"]
                
                # Find corresponding frame
                frame_data = None
                for frame in batch_data["frames"]:
                    if frame["frame_id"] == frame_id:
                        frame_data = frame["data"]
                        break
                
                if frame_data and detections:
                    # Add annotations
                    annotated_frame = self.draw_annotations(frame_data, detections)
                    processed_frames.append({
                        "frame_id": frame_id,
                        "original_frame": frame_data,
                        "annotated_frame": annotated_frame,
                        "detections": detections
                    })
            
            processed_results["annotated_frames"] = processed_frames
            processed_results["post_processing_time"] = time.time()
            
            return processed_results
            
        except Exception as e:
            print(f"Post-processing error: {e}")
            return inference_results
    
    def upload_to_s3(self, data, batch_id):
        """Upload results to S3"""
        if not self.s3_client:
            print("S3 client not available, skipping upload")
            return False
        
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            
            # Upload main results
            results_key = f"results/batch_{batch_id}_{timestamp}.json"
            self.s3_client.put_object(
                Bucket=self.s3_bucket,
                Key=results_key,
                Body=json.dumps(data, indent=2),
                ContentType="application/json"
            )
            
            # Upload annotated frames if available
            if "annotated_frames" in data:
                for frame_data in data["annotated_frames"]:
                    frame_id = frame_data["frame_id"]
                    if frame_data.get("annotated_frame"):
                        frame_key = f"annotated_frames/batch_{batch_id}_frame_{frame_id}_{timestamp}.jpg"
                        
                        # Decode and upload frame
                        img_data = base64.b64decode(frame_data["annotated_frame"])
                        self.s3_client.put_object(
                            Bucket=self.s3_bucket,
                            Key=frame_key,
                            Body=img_data,
                            ContentType="image/jpeg"
                        )
            
            print(f"✓ Uploaded to S3: {results_key}")
            return True
            
        except Exception as e:
            print(f"S3 upload failed: {e}")
            return False
    
    def process_batch(self, batch_data):
        """Process a single batch"""
        batch_id = batch_data.get("batch_id")
        frame_count = len(batch_data.get("frames", []))
        
        print(f"\n--- Processing Batch {batch_id} ({frame_count} frames) ---")
        
        # Call inference service
        inference_results = self.call_inference(batch_data)
        if not inference_results:
            print(f"✗ Inference failed for batch {batch_id}")
            return
        
        print(f"✓ Inference completed: {inference_results.get('total_detections', 0)} detections")
        
        # Post-process results
        processed_results = self.post_process_results(batch_data, inference_results)
        
        # Upload to S3
        if self.upload_to_s3(processed_results, batch_id):
            print(f"✓ Batch {batch_id} processing complete")
        else:
            print(f"⚠ Batch {batch_id} processed but S3 upload failed")
    
    def run(self):
        """Main consumer loop"""
        print("Starting OptifYe Consumer...")
        print(f"Listening on topic: {self.kafka_topic}")
        print("Waiting for messages...\n")
        
        try:
            for message in self.consumer:
                try:
                    batch_data = message.value
                    self.process_batch(batch_data)
                    
                except Exception as e:
                    print(f"Error processing message: {e}")
                    continue
                    
        except KeyboardInterrupt:
            print("\nShutting down consumer...")
        except Exception as e:
            print(f"Consumer error: {e}")
        finally:
            self.consumer.close()
            print("Consumer stopped")

if __name__ == "__main__":
    consumer = OptifYeConsumer()
    consumer.run()
