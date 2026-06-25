const express = require('express');
const dotenv = require('dotenv');
const axios = require('axios');
const { createLogger, format, transports } = require('winston');

// Standardized JSON logger. Always emits: timestamp, level, service, message,
// plus any extra fields passed per call (method, path, status_code, etc.).
const logger = createLogger({
  level: 'info',
  defaultMeta: { service: 'nodejs' },
  format: format.combine(
    format.timestamp(),
    format.json()
  ),
  transports: [
    new transports.Console()
  ]
});

dotenv.config();

const app = express();
const port = process.env.PORT || 3000;
const PYTHON_SERVICE_URL = process.env.PYTHON_SERVICE_URL;
const UPSTREAM = 'python';

app.get('/nodejs', async (req, res) => {
  const start = Date.now();
  logger.info('request received', { method: req.method, path: req.path });

  try {
    logger.info('calling upstream', { upstream: UPSTREAM });
    const upstreamRes = await axios.get(PYTHON_SERVICE_URL, {
      headers: { 'X-Request-ID': req.header('X-Request-ID') || '' }
    });
    logger.info('upstream responded', { upstream: UPSTREAM, status_code: upstreamRes.status });

    const body = {
      service: 'nodejs',
      message: 'Hello from nodejs',
      status: 'ok',
      timestamp: new Date().toISOString(),
      upstream: upstreamRes.data
    };

    logger.info('request completed', {
      method: req.method, path: req.path, status_code: 200, duration_ms: Date.now() - start
    });
    res.json(body);
  } catch (err) {
    logger.error('upstream call failed', { upstream: UPSTREAM, error: err.message });

    const body = {
      service: 'nodejs',
      message: 'Hello from nodejs',
      status: 'error',
      timestamp: new Date().toISOString(),
      upstream: null,
      error: err.message
    };

    logger.info('request completed', {
      method: req.method, path: req.path, status_code: 502, duration_ms: Date.now() - start
    });
    res.status(502).json(body);
  }
});

app.listen(port, () => {
  logger.info('server started', { port });
});
