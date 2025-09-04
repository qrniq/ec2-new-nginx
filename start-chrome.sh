#!/bin/bash

# Chrome Headless Startup Script for Remote Debugging
# Starts Google Chrome in headless mode with remote debugging enabled
# Default port: 48333 (configurable via PORT environment variable)
# Port range: 48000-49000

set -euo pipefail

# Configuration
DEFAULT_PORT=48333
CHROME_PORT=${PORT:-$DEFAULT_PORT}
CHROME_USER_DATA_DIR="/tmp/chrome-debug-$(date +%s)"
CHROME_EXECUTABLE="/usr/bin/google-chrome"
CHROME_LOG_FILE="/var/log/chrome-debug.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$CHROME_LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$CHROME_LOG_FILE" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$CHROME_LOG_FILE"
}

# Check if port is in valid range
validate_port() {
    if [ "$CHROME_PORT" -lt 48000 ] || [ "$CHROME_PORT" -gt 49000 ]; then
        error "Port $CHROME_PORT is outside allowed range 48000-49000"
        exit 1
    fi
}

# Check if port is available
check_port_available() {
    if lsof -Pi :$CHROME_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        warn "Port $CHROME_PORT is already in use"
        # Try to find next available port in range
        for ((port=48000; port<=49000; port++)); do
            if ! lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
                CHROME_PORT=$port
                log "Using available port: $CHROME_PORT"
                break
            fi
        done
        
        # Check if we found an available port
        if lsof -Pi :$CHROME_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
            error "No available ports in range 48000-49000"
            exit 1
        fi
    fi
}

# Check if Chrome executable exists
check_chrome_executable() {
    if [ ! -x "$CHROME_EXECUTABLE" ]; then
        # Try alternative locations
        ALTERNATIVES=("/opt/google/chrome/google-chrome" "/usr/bin/chromium-browser" "/usr/bin/chromium")
        for alt in "${ALTERNATIVES[@]}"; do
            if [ -x "$alt" ]; then
                CHROME_EXECUTABLE="$alt"
                log "Using Chrome executable: $CHROME_EXECUTABLE"
                return 0
            fi
        done
        error "Chrome executable not found. Please install Google Chrome or Chromium."
        exit 1
    fi
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    if [ -n "${CHROME_PID:-}" ]; then
        log "Terminating Chrome process (PID: $CHROME_PID)"
        kill -TERM "$CHROME_PID" 2>/dev/null || true
        sleep 2
        kill -KILL "$CHROME_PID" 2>/dev/null || true
    fi
    
    if [ -d "$CHROME_USER_DATA_DIR" ]; then
        log "Removing temporary user data directory: $CHROME_USER_DATA_DIR"
        rm -rf "$CHROME_USER_DATA_DIR"
    fi
    
    log "Cleanup completed"
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Main execution
main() {
    log "Starting Chrome headless debugging server..."
    log "Configuration:"
    log "  Port: $CHROME_PORT"
    log "  User Data Dir: $CHROME_USER_DATA_DIR"
    log "  Chrome Executable: $CHROME_EXECUTABLE"
    
    # Validation checks
    validate_port
    check_port_available
    check_chrome_executable
    
    # Create user data directory
    mkdir -p "$CHROME_USER_DATA_DIR"
    
    # Chrome command line arguments for headless debugging
    CHROME_ARGS=(
        "--headless=new"
        "--no-sandbox"
        "--disable-dev-shm-usage"
        "--disable-gpu"
        "--disable-software-rasterizer"
        "--disable-background-timer-throttling"
        "--disable-backgrounding-occluded-windows"
        "--disable-renderer-backgrounding"
        "--disable-features=TranslateUI,VizDisplayCompositor"
        "--disable-extensions"
        "--disable-plugins"
        "--disable-default-apps"
        "--disable-sync"
        "--disable-translate"
        "--hide-scrollbars"
        "--mute-audio"
        "--no-first-run"
        "--safebrowsing-disable-auto-update"
        "--disable-web-security"
        "--disable-features=VizDisplayCompositor"
        "--remote-debugging-port=$CHROME_PORT"
        "--remote-debugging-address=127.0.0.1"
        "--user-data-dir=$CHROME_USER_DATA_DIR"
        "--window-size=1920,1080"
        "--virtual-time-budget=5000"
    )
    
    log "Starting Chrome with arguments: ${CHROME_ARGS[*]}"
    
    # Start Chrome in background
    "$CHROME_EXECUTABLE" "${CHROME_ARGS[@]}" > "$CHROME_LOG_FILE" 2>&1 &
    CHROME_PID=$!
    
    log "Chrome started with PID: $CHROME_PID"
    
    # Wait for Chrome to start and listen on the debug port
    log "Waiting for Chrome debug server to start on port $CHROME_PORT..."
    for i in {1..30}; do
        if curl -s -m 2 "http://127.0.0.1:$CHROME_PORT/json" >/dev/null 2>&1; then
            log "Chrome debug server is ready!"
            break
        fi
        if [ $i -eq 30 ]; then
            error "Chrome debug server failed to start within 30 seconds"
            exit 1
        fi
        sleep 1
    done
    
    # Display connection information
    log "Chrome Remote Debugging Server Information:"
    log "  Debug Port: $CHROME_PORT"
    log "  Local Debug URL: http://127.0.0.1:$CHROME_PORT"
    log "  Process ID: $CHROME_PID"
    log "  Available endpoints:"
    log "    - http://127.0.0.1:$CHROME_PORT/json (targets list)"
    log "    - http://127.0.0.1:$CHROME_PORT/json/version (version info)"
    
    # Test connection
    if command -v curl >/dev/null 2>&1; then
        log "Testing connection..."
        if curl -s "http://127.0.0.1:$CHROME_PORT/json/version" | grep -q "Chrome"; then
            log "Connection test successful!"
        else
            warn "Connection test failed"
        fi
    fi
    
    log "Chrome is running. Press Ctrl+C to stop."
    
    # Keep the script running and monitor Chrome process
    while kill -0 "$CHROME_PID" 2>/dev/null; do
        sleep 5
    done
    
    error "Chrome process has terminated unexpectedly"
    exit 1
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --port PORT    Set Chrome debugging port (default: $DEFAULT_PORT)"
        echo "  --status       Show Chrome process status"
        echo ""
        echo "Environment variables:"
        echo "  PORT           Chrome debugging port (48000-49000)"
        echo ""
        echo "Examples:"
        echo "  $0                    # Start with default port $DEFAULT_PORT"
        echo "  PORT=48500 $0         # Start with port 48500"
        echo "  $0 --port 48400       # Start with port 48400"
        exit 0
        ;;
    --port)
        if [ -z "${2:-}" ]; then
            error "Port number required"
            exit 1
        fi
        CHROME_PORT="$2"
        ;;
    --status)
        echo "Chrome Debug Server Status:"
        if pgrep -f "remote-debugging-port" > /dev/null; then
            echo "Status: Running"
            echo "Processes:"
            pgrep -f -l "remote-debugging-port"
            echo "Listening ports:"
            lsof -i -P -n | grep LISTEN | grep -E ":(48[0-9]{3}|49000)"
        else
            echo "Status: Not running"
        fi
        exit 0
        ;;
    "")
        # No arguments, proceed with main
        ;;
    *)
        error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main