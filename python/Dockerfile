# start by pulling the python image
# NOTE: 3.9+ is required — the EDOT/OpenTelemetry Python auto-instrumentation
# injects bundled deps (requests/urllib3) that use 3.9-only syntax
# (functools.cache, runtime tuple[...] subscripting). 3.8 crashes on import.
FROM python:3.12-slim

EXPOSE 5000

# switch working directory
WORKDIR /app

# install the dependencies and packages in the requirements file
COPY python/requirements.txt ./
RUN python -m pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# Then copy the rest of your code
COPY python/. .

# Tell Flask where your app lives
ENV FLASK_APP=app.py

CMD ["flask", "run", "--host=0.0.0.0", "--port=5000"]
