#!/usr/bin/env node

/**
 * Chrome Remote Interface Connection Test
 * 
 * This script tests the nginx reverse proxy connection to headless Chrome
 * and captures a screenshot of a webpage via the Chrome DevTools Protocol.
 * 
 * Requirements:
 * - Chrome running in headless mode with remote debugging enabled
 * - nginx configured as reverse proxy for WebSocket connections
 * - chrome-remote-interface npm package
 * 
 * Usage:
 *   node test-connection.js [options]
 *   
 * Environment Variables:
 *   PROXY_HOST    - nginx proxy host (default: localhost)
 *   PROXY_PORT    - nginx proxy port (default: 80)
 *   TARGET_URL    - URL to capture screenshot (default: https://www.example.com)
 *   OUTPUT_FILE   - Screenshot filename (default: screenshot.png)
 *   CHROME_PORT   - Direct Chrome port for fallback (default: 48333)
 */

const CDP = require('chrome-remote-interface');
const fs = require('fs');
const path = require('path');

// Configuration from environment or defaults
const config = {
    proxyHost: process.env.PROXY_HOST || 'localhost',
    proxyPort: parseInt(process.env.PROXY_PORT) || 80,
    targetUrl: process.env.TARGET_URL || 'https://www.example.com',
    outputFile: process.env.OUTPUT_FILE || 'screenshot.png',
    chromePort: parseInt(process.env.CHROME_PORT) || 48333,
    timeout: 30000,
    useProxy: process.env.USE_DIRECT !== 'true'
};

// Logging utilities
const log = (message) => console.log(`[${new Date().toISOString()}] ${message}`);
const error = (message) => console.error(`[ERROR] ${message}`);
const warn = (message) => console.warn(`[WARN] ${message}`);

/**
 * Test direct connection to Chrome (bypass proxy)
 */
async function testDirectConnection() {
    log(`Testing direct connection to Chrome on port ${config.chromePort}...`);
    
    try {
        const client = await CDP({
            host: 'localhost',
            port: config.chromePort,
            timeout: 5000
        });
        
        await client.close();
        log('Direct Chrome connection successful');
        return true;
    } catch (err) {
        error(`Direct Chrome connection failed: ${err.message}`);
        return false;
    }
}

/**
 * Test proxy connection
 */
async function testProxyConnection() {
    log(`Testing proxy connection via ${config.proxyHost}:${config.proxyPort}...`);
    
    try {
        // Test health endpoint
        const http = require('http');
        
        return new Promise((resolve, reject) => {
            const req = http.get(`http://${config.proxyHost}:${config.proxyPort}/health`, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => {
                    if (res.statusCode === 200) {
                        log('Proxy health check successful');
                        resolve(true);
                    } else {
                        error(`Proxy health check failed with status: ${res.statusCode}`);
                        resolve(false);
                    }
                });
            });
            
            req.on('error', (err) => {
                error(`Proxy connection failed: ${err.message}`);
                resolve(false);
            });
            
            req.setTimeout(5000, () => {
                error('Proxy connection timeout');
                req.destroy();
                resolve(false);
            });
        });
    } catch (err) {
        error(`Proxy test error: ${err.message}`);
        return false;
    }
}

/**
 * Connect to Chrome via proxy and capture screenshot
 */
async function captureScreenshotViaProxy() {
    log('Attempting to connect via nginx proxy...');
    
    let client;
    try {
        // Connect through proxy
        client = await CDP({
            host: config.proxyHost,
            port: config.proxyPort,
            timeout: config.timeout
        });
        
        log('Connected to Chrome via proxy');
        
        // Extract domains for easier access
        const { Network, Page, Runtime, Security } = client;
        
        // Enable necessary domains
        await Network.enable();
        await Page.enable();
        await Runtime.enable();
        await Security.enable();
        
        log('Chrome DevTools domains enabled');
        
        // Set up event handlers
        Page.loadEventFired(() => {
            log('Page load event fired');
        });
        
        Network.responseReceived((params) => {
            if (params.response.status >= 400) {
                warn(`HTTP ${params.response.status}: ${params.response.url}`);
            }
        });
        
        // Ignore certificate errors
        Security.setIgnoreCertificateErrors({ ignore: true });
        
        // Navigate to target URL
        log(`Navigating to: ${config.targetUrl}`);
        await Page.navigate({ url: config.targetUrl });
        
        // Wait for page to load
        log('Waiting for page to load...');
        await Page.loadEventFired();
        
        // Additional wait for dynamic content
        await new Promise(resolve => setTimeout(resolve, 3000));
        
        // Get page metrics
        const metrics = await Page.getLayoutMetrics();
        log(`Page dimensions: ${metrics.layoutViewport.clientWidth}x${metrics.layoutViewport.clientHeight}`);
        
        // Capture screenshot
        log('Capturing screenshot...');
        const screenshot = await Page.captureScreenshot({
            format: 'png',
            quality: 90,
            fromSurface: true,
            captureBeyondViewport: false
        });
        
        // Save screenshot to file
        const outputPath = path.resolve(config.outputFile);
        fs.writeFileSync(outputPath, screenshot.data, 'base64');
        
        log(`Screenshot saved successfully: ${outputPath}`);
        log(`File size: ${fs.statSync(outputPath).size} bytes`);
        
        return true;
        
    } catch (err) {
        error(`Screenshot capture failed: ${err.message}`);
        if (err.code === 'ECONNREFUSED') {
            error('Connection refused - check if nginx proxy is running');
        } else if (err.code === 'ETIMEDOUT') {
            error('Connection timeout - check proxy configuration');
        }
        return false;
    } finally {
        if (client) {
            try {
                await client.close();
                log('Chrome connection closed');
            } catch (err) {
                warn(`Error closing connection: ${err.message}`);
            }
        }
    }
}

/**
 * Fallback: Direct connection to Chrome
 */
async function captureScreenshotDirect() {
    log('Attempting direct connection to Chrome...');
    
    let client;
    try {
        client = await CDP({
            host: 'localhost',
            port: config.chromePort,
            timeout: config.timeout
        });
        
        log('Connected to Chrome directly');
        
        const { Network, Page, Runtime, Security } = client;
        
        await Network.enable();
        await Page.enable();
        await Runtime.enable();
        await Security.enable();
        
        Security.setIgnoreCertificateErrors({ ignore: true });
        
        log(`Navigating to: ${config.targetUrl}`);
        await Page.navigate({ url: config.targetUrl });
        await Page.loadEventFired();
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        log('Capturing screenshot (direct connection)...');
        const screenshot = await Page.captureScreenshot({
            format: 'png',
            quality: 90,
            fromSurface: true
        });
        
        const fallbackFile = 'screenshot-direct.png';
        fs.writeFileSync(fallbackFile, screenshot.data, 'base64');
        
        log(`Screenshot saved via direct connection: ${fallbackFile}`);
        return true;
        
    } catch (err) {
        error(`Direct screenshot capture failed: ${err.message}`);
        return false;
    } finally {
        if (client) {
            try {
                await client.close();
            } catch (err) {
                warn(`Error closing direct connection: ${err.message}`);
            }
        }
    }
}

/**
 * Display Chrome targets information
 */
async function displayTargetsInfo() {
    try {
        log('Fetching Chrome targets information...');
        
        const targets = await CDP.List({
            host: config.useProxy ? config.proxyHost : 'localhost',
            port: config.useProxy ? config.proxyPort : config.chromePort
        });
        
        log(`Found ${targets.length} Chrome target(s):`);
        targets.forEach((target, index) => {
            log(`  Target ${index + 1}:`);
            log(`    ID: ${target.id}`);
            log(`    Type: ${target.type}`);
            log(`    URL: ${target.url}`);
            log(`    Title: ${target.title || 'N/A'}`);
            log(`    WebSocket: ${target.webSocketDebuggerUrl || 'N/A'}`);
        });
        
        return targets;
    } catch (err) {
        error(`Failed to fetch targets: ${err.message}`);
        return [];
    }
}

/**
 * Main execution function
 */
async function main() {
    log('Chrome Remote Interface Connection Test');
    log('=====================================');
    log(`Configuration:`);
    log(`  Proxy: ${config.proxyHost}:${config.proxyPort}`);
    log(`  Target URL: ${config.targetUrl}`);
    log(`  Output File: ${config.outputFile}`);
    log(`  Chrome Port: ${config.chromePort}`);
    log(`  Use Proxy: ${config.useProxy}`);
    log('');
    
    try {
        // Test connections
        const proxyHealthy = await testProxyConnection();
        const chromeReachable = await testDirectConnection();
        
        if (!chromeReachable) {
            error('Chrome is not reachable. Please ensure Chrome is running with remote debugging enabled.');
            error('Start Chrome with: ./start-chrome.sh');
            process.exit(1);
        }
        
        // Display targets information
        await displayTargetsInfo();
        
        let success = false;
        
        // Try proxy connection first (if proxy is healthy)
        if (config.useProxy && proxyHealthy) {
            log('Attempting screenshot capture via nginx proxy...');
            success = await captureScreenshotViaProxy();
        }
        
        // Fallback to direct connection if proxy failed or not used
        if (!success) {
            if (config.useProxy) {
                warn('Proxy connection failed, falling back to direct connection...');
            } else {
                log('Using direct connection to Chrome...');
            }
            success = await captureScreenshotDirect();
        }
        
        if (success) {
            log('');
            log('✅ Test completed successfully!');
            log('Screenshot capture and proxy connection working correctly.');
            
            // Verify screenshot file exists and has content
            if (fs.existsSync(config.outputFile)) {
                const stats = fs.statSync(config.outputFile);
                log(`Screenshot file verified: ${config.outputFile} (${stats.size} bytes)`);
            }
        } else {
            error('❌ Test failed!');
            error('Unable to capture screenshot via proxy or direct connection.');
            process.exit(1);
        }
        
    } catch (err) {
        error(`Unexpected error: ${err.message}`);
        console.error(err.stack);
        process.exit(1);
    }
}

// Handle command line arguments
const args = process.argv.slice(2);
if (args.includes('--help') || args.includes('-h')) {
    console.log('Chrome Remote Interface Connection Test');
    console.log('');
    console.log('Usage: node test-connection.js [options]');
    console.log('');
    console.log('Options:');
    console.log('  --help, -h     Show this help message');
    console.log('  --direct       Use direct Chrome connection (bypass proxy)');
    console.log('');
    console.log('Environment Variables:');
    console.log('  PROXY_HOST     nginx proxy host (default: localhost)');
    console.log('  PROXY_PORT     nginx proxy port (default: 80)');
    console.log('  TARGET_URL     URL to capture (default: https://www.example.com)');
    console.log('  OUTPUT_FILE    Screenshot filename (default: screenshot.png)');
    console.log('  CHROME_PORT    Direct Chrome port (default: 48333)');
    console.log('  USE_DIRECT     Set to "true" to bypass proxy');
    console.log('');
    console.log('Examples:');
    console.log('  node test-connection.js');
    console.log('  TARGET_URL=https://google.com node test-connection.js');
    console.log('  USE_DIRECT=true node test-connection.js');
    process.exit(0);
}

if (args.includes('--direct')) {
    config.useProxy = false;
    log('Direct mode enabled - bypassing proxy');
}

// Handle process signals
process.on('SIGINT', () => {
    log('Received SIGINT, shutting down gracefully...');
    process.exit(0);
});

process.on('SIGTERM', () => {
    log('Received SIGTERM, shutting down gracefully...');
    process.exit(0);
});

// Run main function
if (require.main === module) {
    main().catch((err) => {
        error(`Fatal error: ${err.message}`);
        console.error(err.stack);
        process.exit(1);
    });
}