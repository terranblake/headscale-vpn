# OpenHands Installation Guide for Multi-Agent Execution

## Quick Fix for Dependency Conflicts

The error you're seeing is a common issue with OpenHands dependency resolution. Here are several solutions:

## Solution 1: Use Docker (Recommended)

This avoids all dependency conflicts and is the most reliable approach:

```bash
# 1. Install Docker if not already installed
# On Ubuntu/Debian:
sudo apt update && sudo apt install docker.io docker-compose

# On macOS:
brew install docker

# On Windows:
# Download Docker Desktop from docker.com

# 2. Pull the OpenHands Docker image
docker pull ghcr.io/all-hands-ai/openhands:main

# 3. Create a wrapper script for easy agent launching
cat > run-openhands-agent.sh << 'EOF'
#!/bin/bash
AGENT_NAME=${1:-"openhands-agent"}
CONFIG_FILE=${2:-".openhands/project-config.yaml"}
WORKSPACE_DIR=${3:-"$(pwd)"}

docker run -it --rm \
  -v "$WORKSPACE_DIR:/workspace" \
  -v ~/.gitconfig:/root/.gitconfig:ro \
  -e GITHUB_TOKEN="$GITHUB_TOKEN" \
  --name "$AGENT_NAME" \
  ghcr.io/all-hands-ai/openhands:main \
  --config "/workspace/$CONFIG_FILE" \
  --workspace-dir /workspace
EOF

chmod +x run-openhands-agent.sh
```

## Solution 2: Use Conda Environment

Conda handles dependency conflicts better than pip:

```bash
# 1. Install Miniconda if not already installed
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh

# 2. Create a new conda environment
conda create -n openhands python=3.9
conda activate openhands

# 3. Install OpenHands with conda-forge
conda install -c conda-forge openhands-ai

# Alternative: Install with relaxed dependencies
pip install --no-deps openhands-ai
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip install mediapipe==0.8.7.3 --force-reinstall
```

## Solution 3: Manual Dependency Resolution

If you prefer to stick with pip and venv:

```bash
# 1. Create fresh virtual environment
python3 -m venv openhands-env
source openhands-env/bin/activate  # On Windows: openhands-env\Scripts\activate

# 2. Upgrade pip and install build tools
pip install --upgrade pip setuptools wheel

# 3. Install dependencies in specific order
pip install torch==1.9.0 --index-url https://download.pytorch.org/whl/cpu
pip install mediapipe==0.8.7.3 --no-deps
pip install opencv-python==4.5.3.56
pip install numpy==1.21.0

# 4. Install OpenHands with no dependencies check
pip install --no-deps openhands-ai

# 5. Install remaining dependencies manually
pip install requests aiohttp pydantic fastapi uvicorn
```

## Solution 4: Use Development Version

The latest development version often has better dependency management:

```bash
# 1. Fresh virtual environment
python3 -m venv openhands-dev
source openhands-dev/bin/activate

# 2. Install from GitHub directly
pip install git+https://github.com/All-Hands-AI/OpenHands.git

# 3. If that fails, clone and install locally
git clone https://github.com/All-Hands-AI/OpenHands.git
cd OpenHands
pip install -e .
```

## Multi-Agent Docker Setup (Recommended for You)

Since you have a beefy gaming machine, Docker is perfect for running multiple agents:

```bash
# 1. Create docker-compose.yml for multi-agent setup
cat > docker-compose-agents.yml << 'EOF'
version: '3.8'

services:
  documentation-agent:
    image: ghcr.io/all-hands-ai/openhands:main
    container_name: documentation-agent
    volumes:
      - .:/workspace
      - ~/.gitconfig:/root/.gitconfig:ro
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}
    command: --config /workspace/.openhands/agents/documentation-agent.yaml --workspace-dir /workspace
    working_dir: /workspace

  infrastructure-agent:
    image: ghcr.io/all-hands-ai/openhands:main
    container_name: infrastructure-agent
    volumes:
      - .:/workspace
      - ~/.gitconfig:/root/.gitconfig:ro
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}
    command: --config /workspace/.openhands/agents/infrastructure-agent.yaml --workspace-dir /workspace
    working_dir: /workspace

  family-experience-agent:
    image: ghcr.io/all-hands-ai/openhands:main
    container_name: family-experience-agent
    volumes:
      - .:/workspace
      - ~/.gitconfig:/root/.gitconfig:ro
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}
    command: --config /workspace/.openhands/agents/family-experience-agent.yaml --workspace-dir /workspace
    working_dir: /workspace

  operations-agent:
    image: ghcr.io/all-hands-ai/openhands:main
    container_name: operations-agent
    volumes:
      - .:/workspace
      - ~/.gitconfig:/root/.gitconfig:ro
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}
    command: --config /workspace/.openhands/agents/operations-agent.yaml --workspace-dir /workspace
    working_dir: /workspace

  monitor-agent:
    image: ghcr.io/all-hands-ai/openhands:main
    container_name: monitor-agent
    volumes:
      - .:/workspace
      - ~/.gitconfig:/root/.gitconfig:ro
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}
    command: --config /workspace/.openhands/agents/monitor-agent.yaml --workspace-dir /workspace
    working_dir: /workspace
EOF

# 2. Start all agents
export GITHUB_TOKEN="your_github_token_here"
docker-compose -f docker-compose-agents.yml up -d

# 3. Monitor agents
docker-compose -f docker-compose-agents.yml logs -f

# 4. Stop agents when done
docker-compose -f docker-compose-agents.yml down
```

## Alternative: OpenHands Cloud

If local installation continues to be problematic, you can use OpenHands Cloud:

```bash
# 1. Sign up at https://app.all-hands.dev/
# 2. Upload your project repository
# 3. Configure 5 separate agent instances with your agent configs
# 4. Start agents with coordination protocols
```

## Troubleshooting Common Issues

### Issue: Python Version Conflicts
```bash
# Use Python 3.9 specifically
pyenv install 3.9.18
pyenv local 3.9.18
python -m venv openhands-env
```

### Issue: CUDA/GPU Dependencies
```bash
# Install CPU-only versions
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
```

### Issue: MediaPipe Conflicts
```bash
# Force reinstall with specific version
pip uninstall mediapipe
pip install mediapipe==0.8.7.3 --force-reinstall --no-cache-dir
```

## Recommended Approach for Your Setup

Given your gaming machine specs, I recommend:

1. **Docker approach** - Most reliable, no dependency conflicts
2. **Use docker-compose** for easy multi-agent management
3. **Monitor with Portainer** (optional) for GUI management

```bash
# Quick start with Docker
cd headscale-vpn
docker pull ghcr.io/all-hands-ai/openhands:main
# Use the docker-compose setup above
```

This avoids all Python dependency issues and gives you a clean, reproducible environment for all 5 agents!