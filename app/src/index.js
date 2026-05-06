'use strict';

const express = require('express');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;
const SERVICE_VERSION = process.env.SERVICE_VERSION || '1.0.0';

// Middleware
app.use(express.json());

// Request logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    console.log(
      JSON.stringify({
        timestamp: new Date().toISOString(),
        method: req.method,
        path: req.path,
        status: res.statusCode,
        duration_ms: Date.now() - start,
        user_agent: req.headers['user-agent'],
      })
    );
  });
  next();
});

// Routes
app.get('/', (req, res) => {
  res.json({
    message: 'Hello from DevOps Challenge App!',
    version: SERVICE_VERSION,
    hostname: os.hostname(),
    uptime_seconds: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    version: SERVICE_VERSION,
    timestamp: new Date().toISOString(),
  });
});

app.get('/ready', (req, res) => {
  // Readiness check — add any dependency checks here (DB, cache, etc.)
  res.status(200).json({ status: 'ready' });
});

app.get('/metrics', (req, res) => {
  res.json({
    uptime_seconds: Math.floor(process.uptime()),
    memory_usage_mb: (process.memoryUsage().heapUsed / 1024 / 1024).toFixed(2),
    cpu_load: os.loadavg(),
    hostname: os.hostname(),
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found', path: req.path });
});

// Error handler
app.use((err, req, res, _next) => {
  console.error(JSON.stringify({ level: 'error', message: err.message, stack: err.stack }));
  res.status(500).json({ error: 'Internal server error' });
});

// Graceful shutdown
const server = app.listen(PORT, () => {
  console.log(JSON.stringify({ level: 'info', message: `Server started`, port: PORT, version: SERVICE_VERSION }));
});

const shutdown = (signal) => {
  console.log(JSON.stringify({ level: 'info', message: `${signal} received, shutting down gracefully` }));
  server.close(() => {
    console.log(JSON.stringify({ level: 'info', message: 'Server closed' }));
    process.exit(0);
  });
  setTimeout(() => {
    console.error(JSON.stringify({ level: 'error', message: 'Forced shutdown after timeout' }));
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = app;
