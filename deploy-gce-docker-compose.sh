#!/bin/bash
# deploy-gce-docker-compose.sh
# Deploy the full docker-compose stack to a Google Compute Engine VM

PROJECT_ID="lifecalendar-387215"
ZONE="us-central1-a"
INSTANCE_NAME="gemini-langgraph-app"
MACHINE_TYPE="e2-standard-2"  # 2 vCPUs, 8GB RAM

echo "🚀 Deploying full stack to Google Compute Engine..."

# Create firewall rule for port 8123
echo "🔥 Creating firewall rule..."
gcloud compute firewall-rules create allow-langgraph \
  --allow tcp:8123 \
  --source-ranges 0.0.0.0/0 \
  --target-tags langgraph-app \
  --project $PROJECT_ID 2>/dev/null || echo "Firewall rule already exists"

# Create startup script
cat > startup-script.sh << 'EOF'
#!/bin/bash
# Install Docker and Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Clone the repository
cd /home
git clone https://github.com/billster45/gemini-fullstack-langgraph-quickstart.git
cd gemini-fullstack-langgraph-quickstart

# Build the Docker image
sudo docker build -t gemini-fullstack-langgraph -f Dockerfile .

# Create .env file with API keys
cat > .env << ENVFILE
GEMINI_API_KEY=GEMINI_API_KEY_PLACEHOLDER
LANGSMITH_API_KEY=LANGSMITH_API_KEY_PLACEHOLDER
ENVFILE

# Start the application
sudo docker-compose up -d

# Setup auto-restart on reboot
sudo bash -c 'cat > /etc/systemd/system/langgraph.service << SYSTEMD
[Unit]
Description=LangGraph Application
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/gemini-fullstack-langgraph-quickstart
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SYSTEMD'

sudo systemctl enable langgraph.service
EOF

# Replace placeholders with actual API keys
sed -i "s/GEMINI_API_KEY_PLACEHOLDER/$GEMINI_API_KEY/g" startup-script.sh
sed -i "s/LANGSMITH_API_KEY_PLACEHOLDER/$LANGSMITH_API_KEY/g" startup-script.sh

# Create the VM
echo "🖥️  Creating VM instance..."
gcloud compute instances create $INSTANCE_NAME \
  --zone=$ZONE \
  --machine-type=$MACHINE_TYPE \
  --boot-disk-size=50GB \
  --boot-disk-type=pd-standard \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --tags=langgraph-app \
  --metadata-from-file startup-script=startup-script.sh \
  --project=$PROJECT_ID

# Wait for the instance to be ready
echo "⏳ Waiting for instance to be ready..."
sleep 30

# Get the external IP
EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME \
  --zone=$ZONE \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)' \
  --project=$PROJECT_ID)

echo "✅ Deployment initiated!"
echo "📍 Your application will be available at: http://$EXTERNAL_IP:8123/app/"
echo "⏰ Please wait 3-5 minutes for the application to fully start."
echo ""
echo "🔍 To check the status, SSH into the VM:"
echo "   gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID"
echo "   Then run: sudo docker-compose logs -f"
echo ""
echo "💡 To stop the VM (save costs when not using):"
echo "   gcloud compute instances stop $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID"
echo ""
echo "🚀 To start the VM again:"
echo "   gcloud compute instances start $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID"

# Clean up
rm startup-script.sh
