FROM php:8-apache

WORKDIR /var/www/html

RUN apt-get update && apt-get install -y wget unzip git curl && rm -rf /var/lib/apt/lists/*

# --- EDOT PHP: zero-code OpenTelemetry auto-instrumentation ---
# The Elastic distribution ships the OTel extension + SDK + auto-instrumentation in
# one package, so no pecl compile and no open-telemetry/* composer packages are needed.
# The installer auto-detects the PHP version and enables the extension; the OTEL_* env
# vars in all-otel.yaml (OTEL_PHP_AUTOLOAD_ENABLED, endpoint, service name) drive it.
# TARGETARCH is set by Docker buildx to amd64 / arm64, matching the .deb asset names,
# so the correct architecture is selected automatically at build time.
ARG TARGETARCH
ARG EDOT_PHP_VERSION=1.7.0
RUN curl -fsSL -o /tmp/edot-php.deb \
      "https://github.com/elastic/elastic-otel-php/releases/download/v${EDOT_PHP_VERSION}/elastic-otel-php_${EDOT_PHP_VERSION}_${TARGETARCH}.deb" \
    && dpkg -i /tmp/edot-php.deb \
    && rm /tmp/edot-php.deb

# Composer for dependency management (monolog)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY app/ /var/www/html

COPY ./apache/000-default.conf /etc/apache2/sites-available/000-default.conf

RUN composer install --no-dev --no-interaction --working-dir=/var/www/html

EXPOSE 80
