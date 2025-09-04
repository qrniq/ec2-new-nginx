#!/bin/bash

# AWS Linux 2023 Installation Script for nginx and Chrome Debug Proxy
# This script installs nginx, Google Chrome, Node.js, and configures the proxy
# Usage: ./install-aws-linux.sh

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/install-aws-linux-$(date +%Y%m%d-%H%M%S).log"
NGINX_CONFIG_BACKUP="/etc/nginx/nginx.conf.backup-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE" >&2
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Success/failure tracking
declare -a COMPLETED_STEPS=()
declare -a FAILED_STEPS=()

# Cleanup function
cleanup() {
    log "Installation completed with status: ${#FAILED_STEPS[@]} failures"
    if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
        log "✅ All installation steps completed successfully!"
    else
        error "❌ Some steps failed: ${FAILED_STEPS[*]}"
        error "Check log file: $LOG_FILE"
    fi
}

trap cleanup EXIT

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        warn "This script requires sudo privileges. You may be prompted for your password."
        if ! sudo true; then
            error "Unable to obtain sudo privileges. Exiting."
            exit 1
        fi
    fi
}

# Step 1: Update system packages
update_system() {
    log "Step 1: Updating system packages..."
    
    if sudo dnf update -y >> "$LOG_FILE" 2>&1; then
        COMPLETED_STEPS+=("system_update")
        log "✅ System packages updated successfully"
    else
        FAILED_STEPS+=("system_update")
        error "❌ Failed to update system packages"
        return 1
    fi
}

# Step 2: Install nginx
install_nginx() {
    log "Step 2: Installing nginx..."
    
    # Check if nginx is already installed
    if command -v nginx >/dev/null 2>&1; then
        warn "nginx is already installed: $(nginx -v 2>&1)"
        COMPLETED_STEPS+=("nginx_install")
        return 0
    fi
    
    if sudo dnf install -y nginx >> "$LOG_FILE" 2>&1; then
        COMPLETED_STEPS+=("nginx_install")
        log "✅ nginx installed successfully: $(nginx -v 2>&1)"
    else
        FAILED_STEPS+=("nginx_install")
        error "❌ Failed to install nginx"
        return 1
    fi
}

# Step 3: Install Google Chrome
install_chrome() {
    log "Step 3: Installing Google Chrome..."
    
    # Check if chrome is already installed
    if command -v google-chrome >/dev/null 2>&1; then
        warn "Google Chrome is already installed: $(google-chrome --version 2>/dev/null || echo 'version unknown')"
        COMPLETED_STEPS+=("chrome_install")
        return 0
    fi
    
    # Install wget if not present
    if ! command -v wget >/dev/null 2>&1; then
        log "Installing wget..."
        sudo dnf install -y wget >> "$LOG_FILE" 2>&1
    fi
    
    # Add Google signing key
    log "Adding Google signing key..."
    if wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo rpm --import - >> "$LOG_FILE" 2>&1; then
        log "✅ Google signing key added"
    else
        FAILED_STEPS+=("chrome_signing_key")
        error "❌ Failed to add Google signing key"
        return 1
    fi
    
    # Add Google Chrome repository
    log "Adding Google Chrome repository..."
    if sudo dnf config-manager --add-repo https://dl.google.com/linux/chrome/rpm/stable/x86_64 >> "$LOG_FILE" 2>&1; then
        log "✅ Google Chrome repository added"
    else
        FAILED_STEPS+=("chrome_repo")
        error "❌ Failed to add Google Chrome repository"
        return 1
    fi
    
    # Install Google Chrome
    log "Installing Google Chrome stable..."
    if sudo dnf install -y google-chrome-stable >> "$LOG_FILE" 2>&1; then
        COMPLETED_STEPS+=("chrome_install")
        log "✅ Google Chrome installed successfully: $(google-chrome --version 2>/dev/null || echo 'version unknown')"
    else
        FAILED_STEPS+=("chrome_install")
        error "❌ Failed to install Google Chrome"
        return 1
    fi
}

# Step 4: Install Node.js
install_nodejs() {
    log "Step 4: Installing Node.js..."
    
    # Check if node is already installed with appropriate version
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION=$(node -v 2>/dev/null || echo "unknown")
        warn "Node.js is already installed: $NODE_VERSION"
        # Check if it's a suitable version (v14+)
        if [[ "$NODE_VERSION" =~ v1[4-9]\.|v[2-9][0-9]\. ]]; then
            COMPLETED_STEPS+=("nodejs_install")
            return 0
        else
            warn "Node.js version $NODE_VERSION may be too old. Continuing with installation..."
        fi
    fi
    
    # Add NodeSource repository for Node.js 18.x
    log "Adding NodeSource repository for Node.js 18.x..."
    if curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash - >> "$LOG_FILE" 2>&1; then
        log "✅ NodeSource repository added"
    else
        FAILED_STEPS+=("nodejs_repo")
        error "❌ Failed to add NodeSource repository"
        return 1
    fi
    
    # Install Node.js
    log "Installing Node.js..."
    if sudo dnf install -y nodejs >> "$LOG_FILE" 2>&1; then
        COMPLETED_STEPS+=("nodejs_install")
        NODE_VERSION=$(node -v 2>/dev/null || echo "unknown")
        NPM_VERSION=$(npm -v 2>/dev/null || echo "unknown")
        log "✅ Node.js installed successfully: $NODE_VERSION (npm: $NPM_VERSION)"
    else
        FAILED_STEPS+=("nodejs_install")
        error "❌ Failed to install Node.js"
        return 1
    fi
}

# Step 5: Configure nginx
configure_nginx() {
    log "Step 5: Configuring nginx..."
    
    # Backup existing nginx configuration
    if [ -f /etc/nginx/nginx.conf ]; then
        log "Backing up existing nginx configuration..."
        if sudo cp /etc/nginx/nginx.conf "$NGINX_CONFIG_BACKUP" >> "$LOG_FILE" 2>&1; then
            log "✅ nginx configuration backed up to: $NGINX_CONFIG_BACKUP"
        else
            warn "Failed to backup existing nginx configuration"
        fi
    fi
    
    # Copy our nginx configuration
    if [ -f "$SCRIPT_DIR/nginx.conf" ]; then
        log "Copying nginx configuration from project..."
        if sudo cp "$SCRIPT_DIR/nginx.conf" /etc/nginx/nginx.conf >> "$LOG_FILE" 2>&1; then
            log "✅ nginx configuration copied successfully"
        else
            FAILED_STEPS+=("nginx_config_copy")
            error "❌ Failed to copy nginx configuration"
            return 1
        fi
    else
        FAILED_STEPS+=("nginx_config_missing")
        error "❌ nginx.conf not found in $SCRIPT_DIR"
        return 1
    fi
    
    # Test nginx configuration
    log "Testing nginx configuration..."
    if sudo nginx -t >> "$LOG_FILE" 2>&1; then
        COMPLETED_STEPS+=("nginx_config")
        log "✅ nginx configuration test passed"
    else
        FAILED_STEPS+=("nginx_config")
        error "❌ nginx configuration test failed"
        
        # Restore backup if it exists
        if [ -f "$NGINX_CONFIG_BACKUP" ]; then
            log "Restoring nginx configuration backup..."
            sudo cp "$NGINX_CONFIG_BACKUP" /etc/nginx/nginx.conf
        fi
        return 1
    fi
    
    # Create necessary directories
    log "Creating necessary directories..."
    sudo mkdir -p /var/log/nginx /var/cache/nginx /var/lib/nginx >> "$LOG_FILE" 2>&1
    
    # Set appropriate permissions
    sudo chown -R nginx:nginx /var/log/nginx /var/cache/nginx /var/lib/nginx 2>/dev/null || true
}

# Step 6: Install npm dependencies
install_npm_dependencies() {
    log "Step 6: Installing npm dependencies..."
    
    if [ -f "$SCRIPT_DIR/package.json" ]; then
        cd "$SCRIPT_DIR"
        if npm install >> "$LOG_FILE" 2>&1; then
            COMPLETED_STEPS+=("npm_install")
            log "✅ npm dependencies installed successfully"
        else
            FAILED_STEPS+=("npm_install")
            error "❌ Failed to install npm dependencies"
            return 1
        fi
    else
        warn "package.json not found in $SCRIPT_DIR. Skipping npm install."
        COMPLETED_STEPS+=("npm_install")
    fi
}

# Step 7: Start and enable services
start_services() {
    log "Step 7: Starting and enabling services..."
    
    # Enable nginx to start on boot
    log "Enabling nginx service..."
    if sudo systemctl enable nginx >> "$LOG_FILE" 2>&1; then
        log "✅ nginx service enabled for startup"
    else
        warn "Failed to enable nginx service"
    fi
    
    # Start nginx service
    log "Starting nginx service..."
    if sudo systemctl start nginx >> "$LOG_FILE" 2>&1; then
        COMPLETED_STEPS+=("nginx_start")
        log "✅ nginx service started successfully"
    else
        FAILED_STEPS+=("nginx_start")
        error "❌ Failed to start nginx service"
        return 1
    fi
    
    # Check nginx status
    if sudo systemctl is-active nginx >/dev/null 2>&1; then
        log "✅ nginx is running and active"
    else
        warn "nginx service may not be running properly"
    fi
}

# Step 8: Verification and final setup
verify_installation() {
    log "Step 8: Verifying installation..."
    
    # Check nginx is responding
    log "Testing nginx health endpoint..."
    if curl -s -m 5 http://localhost/health >/dev/null 2>&1; then
        log "✅ nginx health check passed"
    else
        warn "nginx health check failed - this may be normal if Chrome is not running yet"
    fi
    
    # Check if required executables are available
    log "Verifying installed components..."
    
    # nginx
    if command -v nginx >/dev/null 2>&1; then
        log "✅ nginx: $(nginx -v 2>&1)"
    else
        error "❌ nginx not found in PATH"
    fi
    
    # Google Chrome
    if command -v google-chrome >/dev/null 2>&1; then
        log "✅ Chrome: $(google-chrome --version 2>/dev/null || echo 'installed but version unknown')"
    else
        error "❌ google-chrome not found in PATH"
    fi
    
    # Node.js
    if command -v node >/dev/null 2>&1; then
        log "✅ Node.js: $(node -v) (npm: $(npm -v))"
    else
        error "❌ node not found in PATH"
    fi
    
    # Check script permissions
    if [ -f "$SCRIPT_DIR/start-chrome.sh" ]; then
        if [ -x "$SCRIPT_DIR/start-chrome.sh" ]; then
            log "✅ start-chrome.sh is executable"
        else
            log "Making start-chrome.sh executable..."
            chmod +x "$SCRIPT_DIR/start-chrome.sh"
        fi
    fi
    
    COMPLETED_STEPS+=("verification")
}

# Display final status and next steps
show_completion_status() {
    echo
    info "==================== INSTALLATION SUMMARY ===================="
    
    if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
        log "🎉 Installation completed successfully!"
        echo
        info "Next steps:"
        info "1. Start Chrome debug server:"
        info "   cd $SCRIPT_DIR"
        info "   ./start-chrome.sh"
        echo
        info "2. Test the setup:"
        info "   npm test"
        echo
        info "3. Access endpoints:"
        info "   - Health check: http://localhost/health"
        info "   - Chrome targets: http://localhost/json"
        info "   - WebSocket debug: http://localhost/devtools/page/[id]"
        echo
        info "4. View logs:"
        info "   - Installation log: $LOG_FILE"
        info "   - nginx logs: /var/log/nginx/"
        info "   - Chrome logs: /var/log/chrome-debug.log (after starting Chrome)"
        echo
    else
        error "❌ Installation completed with ${#FAILED_STEPS[@]} failures"
        error "Failed steps: ${FAILED_STEPS[*]}"
        error "Check the log file for details: $LOG_FILE"
        echo
        info "You may need to:"
        info "1. Check the error messages above"
        info "2. Resolve any dependency issues"
        info "3. Run the script again"
    fi
    
    info "=============================================================="
}

# Main execution
main() {
    info "🚀 Starting AWS Linux 2023 installation for nginx-chrome-debug-proxy"
    info "Log file: $LOG_FILE"
    info "Installation directory: $SCRIPT_DIR"
    echo
    
    # Pre-flight checks
    check_root
    
    # Execute installation steps
    update_system || true
    install_nginx || true
    install_chrome || true
    install_nodejs || true
    configure_nginx || true
    install_npm_dependencies || true
    start_services || true
    verify_installation || true
    
    # Show completion status
    show_completion_status
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "AWS Linux 2023 Installation Script for nginx-chrome-debug-proxy"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --dry-run      Show what would be installed (not implemented)"
        echo
        echo "This script will:"
        echo "  1. Update system packages"
        echo "  2. Install nginx"
        echo "  3. Install Google Chrome"
        echo "  4. Install Node.js 18.x"
        echo "  5. Configure nginx with project configuration"
        echo "  6. Install npm dependencies"
        echo "  7. Start and enable nginx service"
        echo "  8. Verify installation"
        echo
        echo "Requirements:"
        echo "  - AWS Linux 2023"
        echo "  - sudo privileges"
        echo "  - Internet connection"
        echo
        exit 0
        ;;
    "")
        # No arguments, proceed with installation
        ;;
    *)
        error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main installation
main