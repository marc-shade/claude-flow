#!/bin/bash
# Claude-Flow Cluster Deployment Script
# Deploys claude-flow to all nodes in the agentic cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/cluster-config.json"
CLAUDE_FLOW_DIR="$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if jq is available
if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed. Please install it: brew install jq"
    exit 1
fi

log_info "🚀 Claude-Flow Cluster Deployment"
log_info "================================="

# Read cluster configuration
NODES=$(jq -r '.nodes[] | @base64' "$CONFIG_FILE")

# Deploy to local node (mac-studio)
deploy_local() {
    log_info "📦 Deploying to local node (mac-studio)..."

    # Already built, just verify
    if [ ! -d "$CLAUDE_FLOW_DIR/dist" ]; then
        log_error "Build artifacts not found. Run 'npm run build' first."
        exit 1
    fi

    # Link to global npm (optional)
    log_info "Linking claude-flow globally..."
    npm link || log_warning "Global link failed (may already be linked)"

    # Verify installation
    if command -v claude-flow &> /dev/null; then
        VERSION=$(claude-flow --version 2>/dev/null || echo "unknown")
        log_success "✅ Local deployment complete (version: $VERSION)"
    else
        log_warning "claude-flow command not available (may need to restart shell)"
    fi
}

# Deploy to remote node
deploy_remote() {
    local node_data=$1
    local node_id=$(echo "$node_data" | base64 --decode | jq -r '.id')
    local ssh_host=$(echo "$node_data" | base64 --decode | jq -r '.ssh_host')
    local remote_path=$(echo "$node_data" | base64 --decode | jq -r '.paths.claude_flow')
    local role=$(echo "$node_data" | base64 --decode | jq -r '.role')

    if [ "$node_id" = "mac-studio" ]; then
        return # Skip local node in remote deployment
    fi

    log_info "📡 Deploying to $node_id ($role) via $ssh_host..."

    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_host" "echo 'SSH OK'" &>/dev/null; then
        log_error "Cannot connect to $ssh_host. Skipping..."
        return 1
    fi

    # Create remote directory
    log_info "Creating directory: $remote_path"
    ssh "$ssh_host" "mkdir -p '$remote_path'" || {
        log_error "Failed to create directory on $node_id"
        return 1
    }

    # Sync claude-flow files (exclude node_modules, we'll install remotely)
    log_info "Syncing files to $node_id..."
    rsync -avz --delete \
        --exclude 'node_modules' \
        --exclude '.git' \
        --exclude 'dist' \
        --exclude 'dist-cjs' \
        --exclude 'tmp-workspace' \
        --exclude '.swarm' \
        "$CLAUDE_FLOW_DIR/" "$ssh_host:$remote_path/" || {
        log_error "Failed to sync files to $node_id"
        return 1
    }

    # Install dependencies remotely
    log_info "Installing dependencies on $node_id..."
    ssh "$ssh_host" "cd '$remote_path' && npm install --legacy-peer-deps --production" || {
        log_error "Failed to install dependencies on $node_id"
        return 1
    }

    # Build on remote (if needed)
    log_info "Building on $node_id..."
    ssh "$ssh_host" "cd '$remote_path' && npm run build:esm && npm run build:cjs" || {
        log_warning "Build failed on $node_id (may not be critical)"
    }

    # Link globally on remote
    log_info "Linking globally on $node_id..."
    ssh "$ssh_host" "cd '$remote_path' && npm link" || {
        log_warning "Global link failed on $node_id"
    }

    # Verify remote installation
    if ssh "$ssh_host" "command -v claude-flow" &>/dev/null; then
        local remote_version=$(ssh "$ssh_host" "claude-flow --version 2>/dev/null" || echo "unknown")
        log_success "✅ Deployment to $node_id complete (version: $remote_version)"
    else
        log_warning "claude-flow command not available on $node_id"
    fi
}

# Main deployment logic
main() {
    # Deploy to local node first
    deploy_local

    # Deploy to remote nodes in parallel
    log_info ""
    log_info "🌐 Deploying to remote nodes..."

    local pids=()
    for node in $NODES; do
        node_id=$(echo "$node" | base64 --decode | jq -r '.id')
        if [ "$node_id" != "mac-studio" ]; then
            deploy_remote "$node" &
            pids+=($!)
        fi
    done

    # Wait for all deployments
    log_info "Waiting for remote deployments to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid" || log_warning "One or more deployments had warnings"
    done

    log_info ""
    log_success "🎉 Cluster deployment complete!"
    log_info ""
    log_info "Next steps:"
    log_info "1. Run cluster health check: ./verify-cluster.sh"
    log_info "2. Test claude-flow: claude-flow --help"
    log_info "3. Initialize swarm: claude-flow swarm init"
}

main "$@"
