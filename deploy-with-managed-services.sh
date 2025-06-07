#!/bin/bash
# deploy-with-managed-services.sh
# Deploy to Cloud Run with Cloud SQL and Memorystore

PROJECT_ID="lifecalendar-387215"
REGION="us-central1"
SERVICE_NAME="gemini-fullstack-langgraph"

echo "🚀 Setting up Cloud Run with managed services..."

# 1. Create Cloud SQL PostgreSQL instance
echo "📦 Creating Cloud SQL instance..."
gcloud sql instances create langgraph-postgres \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region=$REGION \
  --network=default \
  --no-assign-ip

# Create database
gcloud sql databases create postgres \
  --instance=langgraph-postgres

# Create user
gcloud sql users create postgres \
  --instance=langgraph-postgres \
  --password=postgres

# 2. Create Memorystore Redis instance
echo "📦 Creating Memorystore Redis..."
gcloud redis instances create langgraph-redis \
  --size=1 \
  --region=$REGION \
  --redis-version=redis_6_x

# 3. Get connection details
POSTGRES_IP=$(gcloud sql instances describe langgraph-postgres --format="value(ipAddresses[0].ipAddress)")
REDIS_IP=$(gcloud redis instances describe langgraph-redis --region=$REGION --format="value(host)")

# 4. Create VPC connector for Cloud Run
echo "📦 Creating VPC connector..."
gcloud compute networks vpc-access connectors create langgraph-connector \
  --region=$REGION \
  --subnet=default \
  --subnet-project=$PROJECT_ID \
  --min-instances=2 \
  --max-instances=10

# 5. Deploy to Cloud Run with connections
echo "📦 Deploying to Cloud Run..."
gcloud run deploy $SERVICE_NAME \
  --source . \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --set-env-vars GEMINI_API_KEY=$GEMINI_API_KEY,LANGSMITH_API_KEY=$LANGSMITH_API_KEY,REDIS_URI=redis://$REDIS_IP:6379,POSTGRES_URI=postgres://postgres:postgres@$POSTGRES_IP:5432/postgres?sslmode=disable \
  --vpc-connector langgraph-connector \
  --port 8000 \
  --memory 2Gi \
  --timeout 3600 \
  --project $PROJECT_ID

echo "✅ Deployment complete!"
echo "Note: This setup will incur costs for Cloud SQL and Memorystore"
