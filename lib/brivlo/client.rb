# frozen_string_literal: true

require "net/http"
require "json"
require "securerandom"
require "uri"
require "time"
require_relative "config"

module Brivlo
  # HTTP client for sending events to the Brivlo control plane.
  # Designed to fail open: connection errors are logged but never raised.
  class Client
    TIMEOUT = 2

    def initialize
      @endpoint = Config.fetch("BRIVLO_ENDPOINT")
      @token = Config.fetch("BRIVLO_TOKEN")
    end

    def send_event(event:, instance:, host:, **optional)
      return unless @endpoint

      unless @token
        warn "[brivlo] BRIVLO_TOKEN not set, skipping event"
        return
      end

      post(build_payload(event, instance, host, optional))
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      warn "[brivlo] Failed to send event: #{e.message}"
    end

    private

    def build_payload(event, instance, host, optional)
      base = { event_id: SecureRandom.uuid, ts: Time.now.utc.iso8601,
               event: event, instance: instance, host: host }
      base.merge(optional_fields(optional)).compact
    end

    def optional_fields(optional)
      { card: optional[:card], skill: optional[:skill],
        tool: optional[:tool], summary: optional[:summary],
        meta: optional[:meta]&.to_json }
    end

    def post(payload)
      uri = URI.join(@endpoint, "/events")
      http = build_http(uri)

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@token}"
      request.body = JSON.generate(payload)

      response = http.request(request)
      warn "[brivlo] Server returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      http.use_ssl = uri.scheme == "https"
      http
    end
  end
end
