# app.rb
require 'sinatra'
require 'net/http'
require 'uri'
require 'json'
require 'logger'
require 'time'

set :logging, false # replace Sinatra's plain-text access log with our JSON logger

PHP_URL = URI(ENV.fetch('PHP_SERVICE_URL', 'http://all-language-php-lb:80/php'))
UPSTREAM = 'php'

# Standardized JSON logger: timestamp, level, service, message + extra fields.
LOGGER = Logger.new($stdout)
LOGGER.formatter = proc do |severity, datetime, _progname, msg|
  record = {
    timestamp: datetime.utc.iso8601(3),
    level: severity.downcase,
    service: 'ruby'
  }
  if msg.is_a?(Hash)
    record[:message] = msg[:message]
    record.merge!(msg.reject { |k, _| k == :message })
  else
    record[:message] = msg
  end
  JSON.generate(record) + "\n"
end

def http_get(uri)
  Net::HTTP.start(uri.host, uri.port) { |http| http.get(uri.request_uri) }
rescue => e
  e
end

get '/ruby' do
  start = Time.now
  LOGGER.info(message: 'request received', method: request.request_method, path: request.path)

  LOGGER.info(message: 'calling upstream', upstream: UPSTREAM)
  res = http_get(PHP_URL)

  if res.is_a?(Net::HTTPResponse) && res.code.to_i < 400
    LOGGER.info(message: 'upstream responded', upstream: UPSTREAM, status_code: res.code.to_i)
    content_type :json
    body = {
      service: 'ruby',
      message: 'Hello from ruby',
      status: 'ok',
      timestamp: Time.now.utc.iso8601(3),
      upstream: JSON.parse(res.body)
    }
    LOGGER.info(message: 'request completed', method: request.request_method, path: request.path,
                status_code: 200, duration_ms: ((Time.now - start) * 1000).to_i)
    JSON.generate(body)
  else
    error_msg = res.is_a?(Net::HTTPResponse) ? "upstream returned status #{res.code}" : "#{res.class} - #{res.message}"
    LOGGER.error(message: 'upstream call failed', upstream: UPSTREAM, error: error_msg)
    status 502
    content_type :json
    body = {
      service: 'ruby',
      message: 'Hello from ruby',
      status: 'error',
      timestamp: Time.now.utc.iso8601(3),
      upstream: nil,
      error: error_msg
    }
    LOGGER.info(message: 'request completed', method: request.request_method, path: request.path,
                status_code: 502, duration_ms: ((Time.now - start) * 1000).to_i)
    JSON.generate(body)
  end
end
