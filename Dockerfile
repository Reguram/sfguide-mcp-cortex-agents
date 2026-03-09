FROM python:3.13-slim

WORKDIR /app

# Install uv
RUN pip install uv

# Copy project files
COPY pyproject.toml .
COPY cortex_agents.py .

# Install dependencies
RUN uv sync

# Expose the SSE port
EXPOSE 8000

# Set environment variables for SSE transport
ENV MCP_TRANSPORT=sse
ENV MCP_HOST=0.0.0.0
ENV MCP_PORT=8000

# Run the MCP server in SSE mode
CMD ["uv", "run", "--python", "3.13", "cortex_agents.py", "--sse"]
