# Cloud Deployment Guide for Cortex Agent MCP Server

This guide explains how to deploy your MCP server to the cloud for remote access.

## Prerequisites

- Docker installed locally
- Cloud account (AWS, GCP, Azure, or Railway/Render)
- Your Snowflake credentials

## Option 1: Deploy to Railway (Easiest)

[Railway](https://railway.app) is the simplest option for deploying containerized apps.

### Steps:

1. **Push to GitHub** (if not already):
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   gh repo create sfguide-mcp-cortex-agent --public --push
   ```

2. **Deploy to Railway**:
   - Go to [railway.app](https://railway.app)
   - Click "New Project" → "Deploy from GitHub repo"
   - Select your repository
   - Add environment variables in Railway dashboard:
     - `SNOWFLAKE_ACCOUNT_URL`
     - `SNOWFLAKE_PAT`
     - `SEMANTIC_MODEL_FILE`
     - `CORTEX_SEARCH_SERVICE`
     - `MCP_TRANSPORT=sse`
     - `MCP_PORT=8000`

3. **Get your public URL** (e.g., `https://your-app.railway.app`)

---

## Option 2: Deploy to Render

1. Create a `render.yaml` in your repo:
   ```yaml
   services:
     - type: web
       name: cortex-agent-mcp
       runtime: docker
       envVars:
         - key: SNOWFLAKE_ACCOUNT_URL
           sync: false
         - key: SNOWFLAKE_PAT
           sync: false
         - key: SEMANTIC_MODEL_FILE
           sync: false
         - key: CORTEX_SEARCH_SERVICE
           sync: false
         - key: MCP_TRANSPORT
           value: sse
         - key: MCP_PORT
           value: 8000
   ```

2. Connect your GitHub repo at [render.com](https://render.com)

---

## Option 3: Deploy to Azure Container Apps

```bash
# Login to Azure
az login

# Create resource group
az group create --name cortex-mcp-rg --location eastus

# Create container registry
az acr create --resource-group cortex-mcp-rg --name cortexmcpregistry --sku Basic

# Build and push image
az acr build --registry cortexmcpregistry --image cortex-agent-mcp:latest .

# Create container app environment
az containerapp env create \
  --name cortex-mcp-env \
  --resource-group cortex-mcp-rg \
  --location eastus

# Deploy container app
az containerapp create \
  --name cortex-agent-mcp \
  --resource-group cortex-mcp-rg \
  --environment cortex-mcp-env \
  --image cortexmcpregistry.azurecr.io/cortex-agent-mcp:latest \
  --target-port 8000 \
  --ingress external \
  --env-vars \
    SNOWFLAKE_ACCOUNT_URL=<your-url> \
    SNOWFLAKE_PAT=<your-pat> \
    SEMANTIC_MODEL_FILE=<your-file> \
    CORTEX_SEARCH_SERVICE=<your-service> \
    MCP_TRANSPORT=sse \
    MCP_PORT=8000
```

---

## Option 4: Deploy to AWS (ECS/Fargate)

1. Build and push to ECR:
   ```bash
   aws ecr create-repository --repository-name cortex-agent-mcp
   aws ecr get-login-password | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com
   docker build -t cortex-agent-mcp .
   docker tag cortex-agent-mcp:latest <account>.dkr.ecr.<region>.amazonaws.com/cortex-agent-mcp:latest
   docker push <account>.dkr.ecr.<region>.amazonaws.com/cortex-agent-mcp:latest
   ```

2. Create ECS task definition and service with Fargate

---

## Connecting Claude Desktop to Remote MCP Server

Once deployed, update your Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "cortex-agent": {
      "url": "https://your-deployed-url.railway.app/sse"
    }
  }
}
```

---

## Important Notes

### ⚠️ Claude Web Limitation

**Claude Web (claude.ai) does NOT currently support MCP servers** - neither local nor remote. MCP is only available through:
- Claude Desktop application
- Custom applications built with the MCP client SDK

### Security Considerations

1. **Use HTTPS** - Always deploy behind HTTPS in production
2. **Authentication** - Consider adding API key authentication for your SSE endpoint
3. **Secrets Management** - Use your cloud provider's secrets manager instead of environment variables
4. **Network Security** - Restrict access using firewalls/security groups if possible

---

## Testing Your Remote Server Locally

Before deploying, test the SSE mode locally:

```bash
# Run in SSE mode
uv run --python 3.13 cortex_agents.py --sse

# Server will start on http://localhost:8000
# Test with: curl http://localhost:8000/sse
```
