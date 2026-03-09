# Azure Container Apps Deployment Guide

This guide provides step-by-step instructions to deploy the Cortex Agent MCP Server to Azure Container Apps.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Install Azure CLI](#step-1-install-azure-cli)
3. [Step 2: Login to Azure](#step-2-login-to-azure)
4. [Step 3: Set Variables](#step-3-set-variables)
5. [Step 4: Create Resource Group](#step-4-create-resource-group)
6. [Step 5: Create Azure Container Registry](#step-5-create-azure-container-registry)
7. [Step 6: Build and Push Docker Image](#step-6-build-and-push-docker-image)
8. [Step 7: Create Container Apps Environment](#step-7-create-container-apps-environment)
9. [Step 8: Deploy to Azure Container Apps](#step-8-deploy-to-azure-container-apps)
10. [Step 9: Verify Deployment](#step-9-verify-deployment)
11. [Step 10: Configure Claude Desktop](#step-10-configure-claude-desktop)
12. [Cleanup Commands](#cleanup-commands)
13. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, ensure you have:

- [ ] **Azure Account** with permissions to create resources (Contributor role or higher)
- [ ] **Docker Desktop** installed and running ([Download](https://www.docker.com/products/docker-desktop/))
- [ ] **Snowflake Credentials**:
  - `SNOWFLAKE_ACCOUNT_URL` (e.g., `https://FHEFEVD-YVC86223.snowflakecomputing.com`)
  - `SNOWFLAKE_PAT` (Personal Access Token)
  - `SEMANTIC_MODEL_FILE` (e.g., `@DASH_MCP_DB.DATA.SEMANTIC_MODELS/FINANCIAL_SERVICES_ANALYTICS.yaml`)
  - `CORTEX_SEARCH_SERVICE` (e.g., `DASH_MCP_DB.DATA.support_tickets`)

---

## Step 1: Install Azure CLI

### macOS (using Homebrew)

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Azure CLI
brew update && brew install azure-cli
```

### Windows (using MSI installer)

Download and run the MSI installer from: https://aka.ms/installazurecliwindows

### Linux (Ubuntu/Debian)

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### Verify Installation

```bash
az version
```

Expected output shows Azure CLI version (e.g., `2.83.0`)

---

## Step 2: Login to Azure

```bash
# Login to Azure (opens browser)
az login

# If browser doesn't work, use device code:
az login --use-device-code
```

After login, you'll see your subscriptions. Note the subscription ID you want to use.

### Set the subscription (if you have multiple)

```bash
# List all subscriptions
az account list --output table

# Set the desired subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID_OR_NAME"

# Verify current subscription
az account show --output table
```

---

## Step 3: Set Variables

Create these environment variables to use throughout the deployment. **Customize these values:**

```bash
# ============================================
# CUSTOMIZE THESE VALUES
# ============================================

# Azure Resource Configuration
export RESOURCE_GROUP="cortex-mcp-rg"
export LOCATION="eastus"
export ACR_NAME="cortexmcpacr$(openssl rand -hex 4)"  # Must be globally unique, lowercase, no dashes
export CONTAINER_APP_ENV="cortex-mcp-env"
export CONTAINER_APP_NAME="cortex-agent-mcp"

# Snowflake Configuration (REPLACE WITH YOUR VALUES)
export SNOWFLAKE_ACCOUNT_URL="https://FHEFEVD-YVC86223.snowflakecomputing.com"
export SNOWFLAKE_PAT="your-snowflake-personal-access-token"
export SEMANTIC_MODEL_FILE="@DASH_MCP_DB.DATA.SEMANTIC_MODELS/FINANCIAL_SERVICES_ANALYTICS.yaml"
export CORTEX_SEARCH_SERVICE="DASH_MCP_DB.DATA.support_tickets"

# ============================================
# Print variables to verify
# ============================================
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "ACR Name: $ACR_NAME"
echo "Container App Environment: $CONTAINER_APP_ENV"
echo "Container App Name: $CONTAINER_APP_NAME"
```

---

## Step 4: Create Resource Group

```bash
# Create the resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Verify creation
az group show --name $RESOURCE_GROUP --output table
```

**Expected Output:**
```
Location    Name
----------  -------------
eastus      cortex-mcp-rg
```

---

## Step 5: Create Azure Container Registry

```bash
# Create Azure Container Registry (Basic tier is sufficient)
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --admin-enabled true

# Get ACR login server name
export ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)
echo "ACR Login Server: $ACR_LOGIN_SERVER"

# Get ACR credentials
export ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv)
export ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv)

echo "ACR Username: $ACR_USERNAME"
echo "ACR Password: $ACR_PASSWORD"
```

---

## Step 6: Build and Push Docker Image

### Option A: Build locally and push (requires Docker Desktop)

```bash
# Navigate to project directory
cd /Users/Reguram_Manikandan/Documents/Git\ repo/sfguide-mcp-cortex-agent

# Login to ACR
az acr login --name $ACR_NAME

# Build the Docker image
docker build -t cortex-agent-mcp:latest .

# Tag the image for ACR
docker tag cortex-agent-mcp:latest $ACR_LOGIN_SERVER/cortex-agent-mcp:latest

# Push to ACR
docker push $ACR_LOGIN_SERVER/cortex-agent-mcp:latest

# Verify image in ACR
az acr repository list --name $ACR_NAME --output table
```

### Option B: Build using ACR Tasks (no local Docker needed)

```bash
# Navigate to project directory
cd /Users/Reguram_Manikandan/Documents/Git\ repo/sfguide-mcp-cortex-agent

# Build directly in Azure
az acr build \
  --registry $ACR_NAME \
  --image cortex-agent-mcp:latest \
  .

# Verify image in ACR
az acr repository list --name $ACR_NAME --output table
```

---

## Step 7: Create Container Apps Environment

```bash
# Install/upgrade the containerapp extension
az extension add --name containerapp --upgrade

# Register required providers (first time only)
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights

# Wait for providers to register (check status)
az provider show --namespace Microsoft.App --query "registrationState" --output tsv
az provider show --namespace Microsoft.OperationalInsights --query "registrationState" --output tsv

# Create Container Apps Environment
az containerapp env create \
  --name $CONTAINER_APP_ENV \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION

# Verify environment creation
az containerapp env show \
  --name $CONTAINER_APP_ENV \
  --resource-group $RESOURCE_GROUP \
  --output table
```

**Note:** Provider registration may take 1-2 minutes. Wait until both show "Registered".

---

## Step 8: Deploy to Azure Container Apps

```bash
# Deploy the container app
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
    MCP_PORT="8000"
```

---

## Step 9: Verify Deployment

```bash
# Get the application URL
export APP_URL=$(az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv)

echo "============================================"
echo "🎉 Deployment Complete!"
echo "============================================"
echo "Application URL: https://$APP_URL"
echo "SSE Endpoint: https://$APP_URL/sse"
echo "============================================"

# Test if the server is responding
curl -I https://$APP_URL

# Check container logs for any errors
az containerapp logs show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --follow
```

Press `Ctrl+C` to stop viewing logs.

---

## Step 10: Configure Claude Desktop

Update your Claude Desktop configuration file:

**macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`

**Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "cortex-agent": {
      "url": "https://YOUR_APP_URL_HERE/sse"
    }
  }
}
```

Replace `YOUR_APP_URL_HERE` with the URL from Step 9.

**Example:**
```json
{
  "mcpServers": {
    "cortex-agent": {
      "url": "https://cortex-agent-mcp.redwater-abc123.eastus.azurecontainerapps.io/sse"
    }
  }
}
```

### Restart Claude Desktop

1. Quit Claude Desktop completely (Cmd+Q on macOS, Alt+F4 on Windows)
2. Reopen Claude Desktop
3. You should see the cortex-agent server connected in the MCP servers panel

---

## Cleanup Commands

When you're done or want to remove all resources:

```bash
# Delete the entire resource group (this deletes everything inside)
az group delete --name $RESOURCE_GROUP --yes --no-wait

# Verify deletion (will show error when fully deleted)
az group show --name $RESOURCE_GROUP
```

---

## Troubleshooting

### Issue: "Authorization Failed" error

**Solution:** Your account doesn't have permission to create resources. Ask your Azure admin for:
- "Contributor" role on the subscription, OR
- "Contributor" role on an existing resource group

### Issue: ACR name already taken

**Solution:** ACR names must be globally unique. Change `ACR_NAME` to something unique:
```bash
export ACR_NAME="cortexmcp$(date +%s)"
```

### Issue: Container app not starting

**Check logs:**
```bash
az containerapp logs show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --tail 100
```

**Check revision status:**
```bash
az containerapp revision list \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --output table
```

### Issue: Cannot connect from Claude Desktop

1. Verify the app is running:
   ```bash
   curl https://$APP_URL/sse
   ```

2. Check the URL format in `claude_desktop_config.json` - must include `/sse` at the end

3. Ensure Claude Desktop was fully restarted after config change

### Issue: Docker build fails

**Check Docker is running:**
```bash
docker info
```

**Use ACR build instead (Option B in Step 6)**

### Issue: Provider not registered

```bash
# Register providers manually
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights

# Wait and check status
sleep 60
az provider show --namespace Microsoft.App --query "registrationState"
```

---

## Quick Reference - All Commands in Order

```bash
# 1. Login
az login

# 2. Set variables (CUSTOMIZE THESE)
export RESOURCE_GROUP="cortex-mcp-rg"
export LOCATION="eastus"
export ACR_NAME="cortexmcpacr$(openssl rand -hex 4)"
export CONTAINER_APP_ENV="cortex-mcp-env"
export CONTAINER_APP_NAME="cortex-agent-mcp"
export SNOWFLAKE_ACCOUNT_URL="https://YOUR_ACCOUNT.snowflakecomputing.com"
export SNOWFLAKE_PAT="your-token"
export SEMANTIC_MODEL_FILE="@YOUR_DB.SCHEMA.SEMANTIC_MODELS/YOUR_MODEL.yaml"
export CORTEX_SEARCH_SERVICE="YOUR_DB.SCHEMA.search_service"

# 3. Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# 4. Create ACR
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true
export ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)
export ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv)
export ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv)

# 5. Build and push image
cd "/path/to/sfguide-mcp-cortex-agent"
az acr build --registry $ACR_NAME --image cortex-agent-mcp:latest .

# 6. Setup Container Apps
az extension add --name containerapp --upgrade
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
az containerapp env create --name $CONTAINER_APP_ENV --resource-group $RESOURCE_GROUP --location $LOCATION

# 7. Deploy
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
    MCP_PORT="8000"

# 8. Get URL
az containerapp show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --query "properties.configuration.ingress.fqdn" --output tsv
```

---

## Cost Estimation

| Resource | Tier | Estimated Monthly Cost |
|----------|------|----------------------|
| Azure Container Registry | Basic | ~$5/month |
| Azure Container Apps | Consumption | ~$0-20/month (pay per use) |
| **Total** | | **~$5-25/month** |

---

## Support

If you encounter issues:
1. Check the [Troubleshooting](#troubleshooting) section above
2. Review Azure Container Apps documentation: https://learn.microsoft.com/azure/container-apps/
3. Check MCP debugging guide: https://modelcontextprotocol.io/docs/tools/debugging
