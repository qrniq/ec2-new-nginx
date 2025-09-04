# Nginx Chrome Debug Proxy

A complete solution for running headless Chrome with nginx reverse proxy for remote debugging access via WebSocket connections. Optimized for AWS EC2 instances running Amazon Linux 2023.

## Overview

This project provides an nginx reverse proxy configuration that enables external access to headless Chrome debugging capabilities through WebSocket connections. Perfect for automated testing, web scraping, and remote debugging scenarios.

### Tech Stack
- **AWS EC2** - Amazon Linux 2023
- **nginx** - Reverse proxy with WebSocket support
- **Google Chrome** - Headless browser with remote debugging
- **Node.js** - Runtime for testing scripts
- **chrome-remote-interface** - Chrome DevTools Protocol client

### Architecture
```
External Client → nginx (port 80) → Chrome Debug Server (port 48333)
                     ↓
                WebSocket Proxy
```

## Quick Start

### 1. Prerequisites (AWS Linux 2023)

```bash
# Update system
sudo dnf update -y

# Install nginx
sudo dnf install -y nginx

# Install Node.js (via NodeSource)
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo dnf install -y nodejs

# Install Google Chrome
sudo dnf install -y wget
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo rpm --import -
sudo dnf config-manager --add-repo https://dl.google.com/linux/chrome/rpm/stable/x86_64
sudo dnf install -y google-chrome-stable

# Install dependencies
npm install
```

### 2. Configuration Setup

```bash
# Copy nginx configuration
sudo cp nginx.conf /etc/nginx/nginx.conf

# Test nginx configuration
sudo nginx -t

# Start nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Check nginx status
sudo systemctl status nginx
```

### 3. Start Chrome Debug Server

```bash
# Start Chrome in headless mode with debugging (port 48333)
./start-chrome.sh

# Or with custom port
PORT=48400 ./start-chrome.sh

# Check status
./start-chrome.sh --status
```

### 4. Test the Setup

```bash
# Run connection test and capture screenshot
npm test

# Or run directly
node test-connection.js

# Test with custom URL
TARGET_URL=https://google.com node test-connection.js
```

## File Structure

```
/root/repo/
├── nginx.conf              # nginx reverse proxy configuration
├── start-chrome.sh          # Chrome headless startup script
├── package.json            # Node.js project configuration
├── test-connection.js      # Connection test and screenshot script
├── screenshot.png          # Generated screenshot (after test)
└── README.md              # This documentation
```

## Configuration Details

### nginx.conf
- **Port 80**: Main proxy and health check endpoint
- **Port 8080**: Alternative direct proxy access
- **WebSocket Support**: Full Chrome DevTools Protocol proxying
- **Health Check**: `/health` endpoint for monitoring
- **Upstream**: Chrome debug server pool with failover

Key endpoints:
- `http://your-server/health` - Health check
- `http://your-server/json` - Chrome targets list
- `http://your-server/devtools/page/[id]` - WebSocket debugging

### start-chrome.sh
- **Port Range**: 48000-49000 (configurable)
- **Default Port**: 48333
- **Auto Port Detection**: Finds available ports automatically
- **Process Management**: Proper cleanup and signal handling
- **Logging**: Comprehensive logging to `/var/log/chrome-debug.log`

Chrome flags used:
```bash
--headless=new --no-sandbox --disable-dev-shm-usage
--remote-debugging-port=48333 --remote-debugging-address=127.0.0.1
--window-size=1920,1080 --disable-gpu --disable-web-security
```

### test-connection.js
- **Proxy Testing**: Validates nginx proxy functionality
- **Direct Connection**: Fallback to direct Chrome connection
- **Screenshot Capture**: Full webpage screenshot capability
- **Error Handling**: Comprehensive error reporting and recovery

Environment variables:
- `PROXY_HOST` - nginx host (default: localhost)
- `PROXY_PORT` - nginx port (default: 80)
- `TARGET_URL` - URL to capture (default: https://www.example.com)
- `OUTPUT_FILE` - Screenshot filename (default: screenshot.png)
- `CHROME_PORT` - Direct Chrome port (default: 48333)

## Usage Examples

### Basic Usage
```bash
# Start Chrome
./start-chrome.sh

# In another terminal, run test
npm test
```

### Custom Configuration
```bash
# Start Chrome on custom port
PORT=48500 ./start-chrome.sh

# Test with custom settings
PROXY_PORT=80 TARGET_URL=https://github.com node test-connection.js
```

### Script Integration
```javascript
const CDP = require('chrome-remote-interface');

// Connect via nginx proxy
const client = await CDP({
    host: 'your-server.com',
    port: 80  // nginx proxy port
});

const { Page } = client;
await Page.enable();
await Page.navigate({ url: 'https://example.com' });
const screenshot = await Page.captureScreenshot();
```

### Health Monitoring
```bash
# Check nginx health
curl http://localhost/health

# Check Chrome status
./start-chrome.sh --status

# View Chrome debug info
curl http://localhost/json
```

## Security Considerations

### Network Access
- Chrome binds to `127.0.0.1` only (no external direct access)
- nginx proxy provides controlled external access
- WebSocket connections are properly proxied

### Chrome Security
- `--no-sandbox` flag required for headless operation
- `--disable-web-security` for cross-origin testing
- Temporary user data directory (cleaned on exit)

### nginx Security
- Rate limiting can be added to location blocks
- SSL/TLS termination support (add SSL configuration)
- Access controls via nginx directives

## Troubleshooting

### Common Issues

**Chrome won't start:**
```bash
# Check Chrome installation
which google-chrome
google-chrome --version

# Check port availability
lsof -i :48333

# Check logs
tail -f /var/log/chrome-debug.log
```

**nginx proxy issues:**
```bash
# Test nginx config
sudo nginx -t

# Check nginx status
sudo systemctl status nginx

# Check nginx logs
sudo tail -f /var/log/nginx/error.log
```

**WebSocket connection failures:**
```bash
# Test direct Chrome connection
curl http://localhost:48333/json

# Test proxy connection
curl http://localhost/json

# Check WebSocket headers
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" http://localhost/json
```

### Performance Tuning

**nginx optimizations:**
```nginx
# Add to http block in nginx.conf
worker_processes auto;
worker_connections 2048;
keepalive_timeout 65;
client_max_body_size 50M;
```

**Chrome optimizations:**
```bash
# Add Chrome flags for better performance
--max_old_space_size=4096
--disable-background-timer-throttling
--disable-renderer-backgrounding
```

## Monitoring and Logs

### Log Locations
- nginx: `/var/log/nginx/access.log`, `/var/log/nginx/error.log`
- Chrome: `/var/log/chrome-debug.log`
- System: `journalctl -u nginx -f`

### Monitoring Commands
```bash
# Monitor nginx access
sudo tail -f /var/log/nginx/access.log

# Monitor Chrome debug log
tail -f /var/log/chrome-debug.log

# Check system resources
htop
netstat -tlnp | grep :80
```

## Production Deployment

### AWS EC2 Setup
1. Launch EC2 instance with Amazon Linux 2023
2. Configure security groups (ports 22, 80, 443)
3. Install prerequisites and copy files
4. Set up systemd services for automatic startup

### Systemd Service (Optional)
Create `/etc/systemd/system/chrome-debug.service`:
```ini
[Unit]
Description=Chrome Debug Server
After=network.target

[Service]
Type=forking
User=ec2-user
WorkingDirectory=/home/ec2-user/nginx-chrome-debug-proxy
ExecStart=/home/ec2-user/nginx-chrome-debug-proxy/start-chrome.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Load Balancing
For multiple Chrome instances:
```nginx
upstream chrome_debug {
    least_conn;
    server 127.0.0.1:48333 weight=10;
    server 127.0.0.1:48334 weight=10;
    server 127.0.0.1:48335 weight=10;
}
```

## API Reference

### nginx Endpoints
- `GET /health` - Health check (returns 200 OK)
- `GET /json` - Chrome targets list
- `GET /json/version` - Chrome version info
- `WebSocket /devtools/page/{pageId}` - Debug WebSocket

### Chrome Remote Interface
```javascript
// List available targets
const targets = await CDP.List({ host: 'localhost', port: 80 });

// Connect to specific target
const client = await CDP({ host: 'localhost', port: 80, target: targets[0] });

// Use Chrome DevTools domains
const { Page, Network, Runtime } = client;
await Page.enable();
await Network.enable();
await Runtime.enable();
```

## Support and Contributing

### Issues
Report issues at: https://github.com/terragon-labs/nginx-chrome-debug-proxy/issues

### Contributing
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### License
MIT License - see LICENSE file for details.

---

**Terragon Labs** - Advanced automation and infrastructure solutions