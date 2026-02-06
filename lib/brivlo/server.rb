# frozen_string_literal: true

require "json"
require "sinatra/base"
require_relative "database"

module Brivlo
  # Sinatra web server for the Brivlo event dashboard.
  class Server < Sinatra::Base
    set :host_authorization, permitted_hosts: []

    def initialize(db: nil)
      super()
      @db = db || Database.connect
      Database.setup(@db)
    end

    before do
      if request.path == "/events" && request.request_method == "POST"
        token = ENV.fetch("BRIVLO_TOKEN", nil)
        provided = request.env["HTTP_AUTHORIZATION"]&.sub(/\ABearer\s+/, "")
        halt 401, "Unauthorized" unless token && provided == token
      end
    end

    get "/ping" do
      "ok"
    end

    post "/events" do
      request.body.rewind
      data = JSON.parse(request.body.read)

      fields = {
        event_id: data["event_id"],
        ts: data["ts"],
        event: data["event"],
        instance: data["instance"],
        host: data["host"],
        card: data["card"],
        skill: data["skill"],
        tool: data["tool"],
        summary: data["summary"],
        meta: data["meta"],
        received_at: Time.now.utc.iso8601
      }

      @db[:events].insert_ignore.insert(fields)
      status 201
      "ok"
    end
  end
end
