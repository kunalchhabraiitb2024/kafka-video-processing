#!/bin/bash
yum update -y

# Install Java 11
yum install -y java-11-amazon-corretto

# Download and install Kafka
cd /opt
wget https://downloads.apache.org/kafka/${kafka_version}/kafka_${kafka_version}.tgz
tar -xzf kafka_${kafka_version}.tgz
mv kafka_${kafka_version} kafka
rm kafka_${kafka_version}.tgz

# Create kafka user
useradd kafka
chown -R kafka:kafka /opt/kafka

# Create systemd service for Zookeeper
cat > /etc/systemd/system/zookeeper.service << EOF
[Unit]
Description=Zookeeper
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
ExecStart=/opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties
ExecStop=/opt/kafka/bin/zookeeper-server-stop.sh
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for Kafka
cat > /etc/systemd/system/kafka.service << EOF
[Unit]
Description=Kafka
After=network.target zookeeper.service

[Service]
Type=simple
User=kafka
Group=kafka
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF

# Update Kafka server.properties for external access
sed -i 's/#listeners=PLAINTEXT:\/\/:9092/listeners=PLAINTEXT:\/\/0.0.0.0:9092/' /opt/kafka/config/server.properties
sed -i "s/#advertised.listeners=PLAINTEXT:\/\/your.host.name:9092/advertised.listeners=PLAINTEXT:\/\/$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4):9092/" /opt/kafka/config/server.properties

# Start services
systemctl daemon-reload
systemctl enable zookeeper kafka
systemctl start zookeeper
sleep 10
systemctl start kafka

# Create video frames topic
sudo -u kafka /opt/kafka/bin/kafka-topics.sh --create --topic video-frames --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1
