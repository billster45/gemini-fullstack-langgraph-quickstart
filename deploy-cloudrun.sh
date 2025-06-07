#!/bin/bash
# Deploy to Google Cloud Run

# Configuration
PROJECT_ID="lifecalendar-387215"
REGION="us-central1"
SERVICE_NAME="gemini-fullstack-langgraph"

echo "🚀 Deploying to Google Cloud Run..."

# First, let's try with the correct port (8000)
echo "📦 Deploying with port 8000..."
gcloud run deploy $SERVICE_NAME \
  --source . \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --set-env-vars GEMINI_API_KEY=$GEMINI_API_KEY,LANGSMITH_API_KEY=$LANGSMITH_API_KEY \
  --port 8000 \
  --memory 2Gi \
  --timeout 3600 \
  --project $PROJECT_ID

echo "✅ Deployment complete!"
