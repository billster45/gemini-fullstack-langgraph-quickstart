#!/bin/bash
# deploy-aws-ec2-docker-compose.sh
# Deploy the full docker-compose stack to AWS EC2

# Configuration
KEY_PAIR_NAME="your-key-pair"  # Change this to your AWS key pair name
INSTANCE_TYPE="t3.medium"       # 2 vCPUs, 4GB RAM
REGION="us-east-1"

echo "🚀 Deploying full stack to AWS EC2..."

# Create security group
echo "🔒 Creating security group..."
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name langgraph-app-sg \
  --description "Security group for LangGraph app" \
  --query 'GroupId' \
  --output text 2>/dev/null || aws ec2 describe-security-groups \
  --group-names langgraph-app-sg \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# Add rules to security group
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port 8123 \
  --cidr 0.0.0.0/0 2>/dev/null || echo "Port 8123 rule already exists"

aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 2>/dev/null || echo "SSH rule already exists"

# Create user data script
cat > user-data.sh << 'EOF'
#!/bin/bash
# Update system
apt-get update
apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Clone the repository
cd /home/ubuntu
git clone https://github.com/billster45/gemini-fullstack-langgraph-quickstart.git
cd gemini-fullstack-langgraph-quickstart
chown -R ubuntu:ubuntu /home/ubuntu/gemini-fullstack-langgraph-quickstart

# Build the Docker image
sudo -u ubuntu docker build -t gemini-fullstack-langgraph -f Dockerfile .

# Create .env file
cat > .env << ENVFILE
GEMINI_API_KEY=GEMINI_API_KEY_PLACEHOLDER
LANGSMITH_API_KEY=LANGSMITH_API_KEY_PLACEHOLDER
ENVFILE

# Start the application
sudo -u ubuntu docker-compose up -d

# Setup auto-restart
cat > /etc/systemd/system/langgraph.service << SYSTEMD
[Unit]
Description=LangGraph Application
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=ubuntu
WorkingDirectory=/home/ubuntu/gemini-fullstack-langgraph-quickstart
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl enable langgraph.service
systemctl start langgraph.service
EOF

# Replace placeholders
sed -i "s/GEMINI_API_KEY_PLACEHOLDER/$GEMINI_API_KEY/g" user-data.sh
sed -i "s/LANGSMITH_API_KEY_PLACEHOLDER/$LANGSMITH_API_KEY/g" user-data.sh

# Get latest Ubuntu AMI
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

# Launch instance
echo "🚀 Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_PAIR_NAME \
  --security-group-ids $SECURITY_GROUP_ID \
  --user-data file://user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=gemini-langgraph-app}]' \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3}' \
  --query 'Instances[0].InstanceId' \
  --output text)

# Wait for instance to be running
echo "⏳ Waiting for instance to start..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "✅ Deployment initiated!"
echo "📍 Your application will be available at: http://$PUBLIC_IP:8123/app/"
echo "⏰ Please wait 3-5 minutes for the application to fully start."
echo ""
echo "🔍 To check the status, SSH into the instance:"
echo "   ssh -i ~/.ssh/$KEY_PAIR_NAME.pem ubuntu@$PUBLIC_IP"
echo "   Then run: docker-compose logs -f"
echo ""
echo "💡 To stop the instance (save costs):"
echo "   aws ec2 stop-instances --instance-ids $INSTANCE_ID"
echo ""
echo "🚀 To start the instance again:"
echo "   aws ec2 start-instances --instance-ids $INSTANCE_ID"
echo ""
echo "🗑️  To terminate the instance:"
echo "   aws ec2 terminate-instances --instance-ids $INSTANCE_ID"

# Clean up
rm user-data.sh
