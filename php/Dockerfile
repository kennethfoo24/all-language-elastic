FROM php:8-apache

WORKDIR /var/www/html

RUN apt-get update && apt-get install -y wget unzip git && rm -rf /var/lib/apt/lists/*

# Composer for dependency management (monolog)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY app/ /var/www/html

COPY ./apache/000-default.conf /etc/apache2/sites-available/000-default.conf

RUN composer install --no-dev --no-interaction --working-dir=/var/www/html

EXPOSE 80
