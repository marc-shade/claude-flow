#!/bin/bash
# Claude-Flow Cluster Verification Script
# Verifies claude-flow installation and health across all cluster nodes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/cluster-config.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check if jq is available
if ! command -v jq &> /dev/null; then
    log_error "jq is required. Install it: brew install jq"
    exit 1
fi

log_info "🔍 Claude-Flow Cluster Verification"
log_info "===================================="
echo ""

# Verify local installation
verify_local() {
    log_info "Checking local node (mac-studio)..."

    # Check if claude-flow is available
    if command -v claude-flow &> /dev/null; then
        VERSION=$(claude-flow --version 2>/dev/null || echo "unknown")
        log_success "claude-flow installed: $VERSION"
    else
        log_error "claude-flow command not found"
        return 1
    fi

    # Check build artifacts
    if [ -d "$SCRIPT_DIR/dist" ] && [ -d "$SCRIPT_DIR/dist-cjs" ]; then
        log_success "Build artifacts present"
    else
        log_warning "Build artifacts missing"
    fi

    # Check node_modules
    if [ -d "$SCRIPT_DIR/node_modules" ]; then
        log_success "Dependencies installed"
    else
        log_error "node_modules missing"
        return 1
    fi

    echo ""
}

# Verify remote node
verify_remote() {
    local node_data=$1
    local node_id=$(echo "$node_data" | base64 --decode | jq -r '.id')
    local ssh_host=$(echo "$node_data" | base64 --decode | jq -r '.ssh_host')
    local remote_path=$(echo "$node_data" | base64 --decode | jq -r '.paths.claude_flow')
    local role=$(echo "$node_data" | base64 --decode | jq -r '.role')

    if [ "$node_id" = "mac-studio" ]; then
        return # Skip local
    fi

    log_info "Checking $node_id ($role) @ $ssh_host..."

    # SSH connectivity
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_host" "echo 'SSH OK'" &>/dev/null; then
        log_error "Cannot connect via SSH"
        return 1
    fi
    log_success "SSH connection OK"

    # Directory exists
    if ssh "$ssh_host" "[ -d '$remote_path' ]"; then
        log_success "Installation directory exists: $remote_path"
    else
        log_error "Installation directory not found: $remote_path"
        return 1
    fi

    # claude-flow command
    if ssh "$ssh_host" "command -v claude-flow" &>/dev/null; then
        VERSION=$(ssh "$ssh_host" "claude-flow --version 2>/dev/null" || echo "unknown")
        log_success "claude-flow available: $VERSION"
    else
        log_warning "claude-flow command not in PATH"
    fi

    # Dependencies
    if ssh "$ssh_host" "[ -d '$remote_path/node_modules' ]"; then
        log_success "Dependencies installed"
    else
        log_warning "node_modules missing"
    fi

    # System info
    local os_info=$(ssh "$ssh_host" "uname -s" 2>/dev/null)
    local node_version=$(ssh "$ssh_host" "node --version" 2>/dev/null || echo "N/A")
    local npm_version=$(ssh "$ssh_host" "npm --version" 2>/dev/null || echo "N/A")

    log_info "OS: $os_info | Node: $node_version | npm: $npm_version"

    echo ""
}

# Main verification
main() {
    verify_local

    # Read nodes from config
    NODES=$(jq -r '.nodes[] | @base64' "$CONFIG_FILE")

    # Verify each remote node
    for node in $NODES; do
        verify_remote "$node"
    done

    log_success "🎉 Cluster verification complete"
    echo ""
    log_info "Summary:"
    log_info "--------"

    # Count successful nodes
    local total=$(jq '.nodes | length' "$CONFIG_FILE")
    log_info "Total nodes: $total"
    log_info "Coordinator: mac-studio"

    # Show capabilities
    echo ""
    log_info "Cluster Capabilities:"
    jq -r '.nodes[] | "  - \(.id): \(.capabilities | join(", "))"' "$CONFIG_FILE"

    echo ""
    log_info "Next steps:"
    log_info "1. Test: claude-flow --help"
    log_info "2. Initialize swarm: claude-flow swarm init"
    log_info "3. Check cluster MCP: mcp__cluster-execution__cluster_status"
}

main "$@"
