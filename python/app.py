from flask import Flask, request, jsonify
import os
import time
import logging
from datetime import datetime, timezone

import requests
from pythonjsonlogger import jsonlogger

app = Flask(__name__)

JAVA_SERVICE_URL = os.getenv('JAVA_SERVICE_URL', 'http://localhost:8080')
UPSTREAM = 'java'


# Standardized JSON logger. Always emits: timestamp, level, service, message,
# plus any extra fields passed via `extra={...}`.
class SchemaJsonFormatter(jsonlogger.JsonFormatter):
    def add_fields(self, log_record, record, message_dict):
        super().add_fields(log_record, record, message_dict)
        log_record['timestamp'] = datetime.now(timezone.utc).isoformat()
        log_record['level'] = record.levelname.lower()
        log_record['service'] = 'python'


logger = logging.getLogger('python')
_handler = logging.StreamHandler()
_handler.setFormatter(SchemaJsonFormatter('%(message)s'))
logger.addHandler(_handler)
logger.setLevel(logging.INFO)
logger.propagate = False
# quiet the default werkzeug access logger so output stays JSON-only
logging.getLogger('werkzeug').setLevel(logging.ERROR)


@app.route('/python')
def hello():
    start = time.time()
    logger.info('request received', extra={'method': request.method, 'path': request.path})

    try:
        logger.info('calling upstream', extra={'upstream': UPSTREAM})
        resp = requests.get(
            f"{JAVA_SERVICE_URL}/java",
            headers={'X-Request-ID': request.headers.get('X-Request-ID', '')},
            timeout=5
        )
        resp.raise_for_status()
        logger.info('upstream responded', extra={'upstream': UPSTREAM, 'status_code': resp.status_code})

        body = {
            'service': 'python',
            'message': 'Hello from python',
            'status': 'ok',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'upstream': resp.json(),
        }
        logger.info('request completed', extra={
            'method': request.method, 'path': request.path,
            'status_code': 200, 'duration_ms': int((time.time() - start) * 1000)
        })
        return jsonify(body), 200
    except Exception as e:
        logger.error('upstream call failed', extra={'upstream': UPSTREAM, 'error': str(e)})
        body = {
            'service': 'python',
            'message': 'Hello from python',
            'status': 'error',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'upstream': None,
            'error': str(e),
        }
        logger.info('request completed', extra={
            'method': request.method, 'path': request.path,
            'status_code': 502, 'duration_ms': int((time.time() - start) * 1000)
        })
        return jsonify(body), 502


if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port)
