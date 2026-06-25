// Local development server for shadertoy projects.
// Serves all files from the workspace root with correct MIME types.
'use strict';

const http = require('http');
const fs   = require('fs');
const path = require('path');

const PORT = parseInt(process.argv[2] || '8080', 10);
const ROOT = __dirname;

const MIME = {
    '.html': 'text/html; charset=utf-8',
    '.js':   'application/javascript; charset=utf-8',
    '.css':  'text/css; charset=utf-8',
    '.glsl': 'text/plain; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png':  'image/png',
    '.jpg':  'image/jpeg',
    '.ico':  'image/x-icon',
};

const server = http.createServer((req, res) => {
    // Strip query string and decode URI
    const urlPath = decodeURIComponent(req.url.split('?')[0]);

    // Resolve to an absolute path, defaulting / to the runner
    let filePath = path.resolve(ROOT, '.' + urlPath);

    // Guard against directory traversal
    if (!filePath.startsWith(ROOT)) {
        res.writeHead(403);
        return res.end('403 Forbidden');
    }

    // Serve index.html for directories
    if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
        filePath = path.join(filePath, 'index.html');
    }

    // Default root to runner
    if (urlPath === '/') {
        filePath = path.join(ROOT, 'runner', 'index.html');
    }

    fs.readFile(filePath, (err, data) => {
        if (err) {
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            return res.end(`404 Not Found: ${urlPath}`);
        }
        const ext         = path.extname(filePath).toLowerCase();
        const contentType = MIME[ext] || 'application/octet-stream';
        res.writeHead(200, { 'Content-Type': contentType });
        res.end(data);
    });
});

server.on('error', (e) => {
    if (e.code === 'EADDRINUSE') {
        console.error(`\n  Error: port ${PORT} is already in use.\n  Stop the existing server first, or pick a different port.\n`);
    } else {
        console.error(e.message);
    }
    process.exit(1);
});

server.listen(PORT, '127.0.0.1');
