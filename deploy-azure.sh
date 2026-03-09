#!/bin/bash

# ============================================
# Azure Container Apps Deployment Script
# Cortex Agent MCP Server
# ============================================

set -e  # Exit on any error

echo "============================================"
echo "Cortex Agent MCP Server - Azure Deployment"
echo "============================================"

# ============================================
# CONFIGURATION - CUSTOMIZE THESE VALUES
# ============================================

# Azure Configuration
RESOURCE_GROUP="cortex-mcp-rg"
LOCATION="eastus"
ACR_NAME="cortexmcpacr$(openssl rand -hex 4)"
CONTAINER_APP_ENV="cortex-mcp-env"
CONTAINER_APP_NAME="cortex-agent-mcp"

# Snowflake Configuration - UPDATE THESE!
SNOWFLAKE_ACCOUNT_URL="${SNOWFLAKE_ACCOUNT_URL:-https://FHEFEVD-YVC86223.snowflakecomputing.com}"
SNOWFLAKE_PAT="${SNOWFLAKE_PAT:-YOUR_SNOWFLAKE_PAT_HERE}"
SEMANTIC_MODEL_FILE="${SEMANTIC_MODEL_FILE:-@DASH_MCP_DB.DATA.SEMANTIC_MODELS/FINANCIAL_SERVICES_ANALYTICS.yaml}"
CORTEX_SEARCH_SERVICE="${CORTEX_SEARCH_SERVICE:-DASH_MCP_DB.DATA.support_tickets}"

# ============================================
# VALIDATION
# ============================================

echo ""
echo "Validating configuration..."

if [ "$SNOWFLAKE_PAT" == "YOUR_SNOWFLAKE_PAT_HERE" ]; then
    echo "❌ ERROR: Please set SNOWFLAKE_PAT environment variable"
    echo "   export SNOWFLAKE_PAT='your-actual-token'"
    exit 1
fi

echo "✅ Configuration validated"
echo ""
echo "Configuration:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  ACR Name: $ACR_NAME"
echo "  Snowflake URL: $SNOWFLAKE_ACCOUNT_URL"
echo ""

# ============================================
# STEP 1: Check Azure Login
# ============================================

echo "Step 1: Checking Azure login..."
if ! az account show &>/dev/null; then
    echo "Not logged in. Opening browser for login..."
    az login
fi
echo "✅ Logged in as: $(az account show --query user.name -o tsv)"
echo "   Subscription: $(az account show --query name -o tsv)"
echo ""

# ============================================
# STEP 2: Create Resource Group
# ============================================

echo "Step 2: Creating resource group '$RESOURCE_GROUP'..."
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION \
    --output none
echo "✅ Resource group created"
echo ""

# ============================================
# STEP 3: Create Azure Container Registry
# ============================================

echo "Step 3: Creating Azure Container Registry '$ACR_NAME'..."
az acr create \
    --resource-group $RESOURCE_GROUP \
    --name $ACR_NAME \
    --sku Basic \
    --admin-enabled true \
    --output none

ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv)

echo "✅ ACR created: $ACR_LOGIN_SERVER"
echo ""

# ============================================
# STEP 4: Build and Push Docker Image
# ============================================

echo "Step 4: Building and pushing Docker image..."
echo "   This may take a few minutes..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

az acr build \
    --registry $ACR_NAME \
    --image cortex-agent-mcp:latest \
    . \
    --output none

echo "✅ Docker image built and pushed"
echo ""

# ============================================
# STEP 5: Setup Container Apps Environment
# ============================================

echo "Step 5: Setting up Container Apps environment..."

# Install extension
az extension add --name containerapp --upgrade --yes 2>/dev/null || true

# Register providers
echo "   Registering providers..."
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait

# Create environment
echo "   Creating Container Apps environment..."
az containerapp env create \
    --name $CONTAINER_APP_ENV \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --output none

echo "✅ Container Apps environment created"
echo ""

# ============================================
# STEP 6: Deploy Container App
# ============================================

echo "Step 6: Deploying Container App..."
echo "   This may take a few minutes..."

az containerapp create \
    --name $CONTAINER_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --environment $CONTAINER_APP_ENV \
    --image $ACR_LOGIN_SERVER/cortex-agent-mcp:latest \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --target-port 8000 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 3 \
    --cpu 0.5 \
    --memory 1.0Gi \
    --env-vars \
        SNOWFLAKE_ACCOUNT_URL="$SNOWFLAKE_ACCOUNT_URL" \
        SNOWFLAKE_PAT="$SNOWFLAKE_PAT" \
        SEMANTIC_MODEL_FILE="$SEMANTIC_MODEL_FILE" \
        CORTEX_SEARCH_SERVICE="$CORTEX_SEARCH_SERVICE" \
        MCP_TRANSPORT="sse" \
        MCP_HOST="0.0.0.0" \
        MCP_PORT="8000" \
    --output none

echo "✅ Container App deployed"
echo ""

# ============================================
# STEP 7: Get Application URL
# ============================================

APP_URL=$(az containerapp show \
    --name $CONTAINER_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "properties.configuration.ingress.fqdn" \
    --output tsv)

echo "============================================"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "============================================"
echo ""
echo "Application URL: https://$APP_URL"
echo "SSE Endpoint:    https://$APP_URL/sse"
echo ""
echo "============================================"
echo "CLAUDE DESKTOP CONFIGURATION"
echo "============================================"
echo ""
echo "Add this to your Claude Desktop config file:"
echo ""
echo "macOS: ~/Library/Application Support/Claude/claude_desktop_config.json"
echo "Windows: %APPDATA%\\Claude\\claude_desktop_config.json"
echo ""
echo '{'
echo '  "mcpServers": {'
echo '    "cortex-agent": {'
echo "      \"url\": \"https://$APP_URL/sse\""
echo '    }'
echo '  }'
echo '}'
echo ""
echo "============================================"
echo ""
echo "To view logs:"
echo "  az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow"
echo ""
echo "To delete all resources:"
echo "  az group delete --name $RESOURCE_GROUP --yes --no-wait"
echo ""
