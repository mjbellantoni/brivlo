# frozen_string_literal: true

require "json"
require "time"
require "sinatra/base"
require_relative "database"

module Brivlo
  # Sinatra web server for the Brivlo event dashboard.
  class Server < Sinatra::Base
    set :host_authorization, permitted_hosts: []
    set :views, File.join(__dir__, "views")
    set :public_folder, File.join(__dir__, "public")

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

    helpers do
      def relative_time(iso_string)
        return "—" unless iso_string

        seconds = Time.now.utc - Time.parse(iso_string)
        case seconds
        when 0...60 then "#{seconds.to_i}s ago"
        when 60...3600 then "#{(seconds / 60).to_i}m ago"
        when 3600...86_400 then "#{(seconds / 3600).to_i}h ago"
        else "#{(seconds / 86_400).to_i}d ago"
        end
      end

      def instance_status(event_name)
        event_name&.start_with?("wait.") ? "waiting" : "active"
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

    get "/board" do
      rows = @db[:events]
             .select_group(:instance)
             .select_append { max(ts).as(latest_ts) }
      instances = rows.map do |row|
        latest = @db[:events]
                 .where(instance: row[:instance], ts: row[:latest_ts])
                 .first
        latest.merge(status: instance_status(latest[:event]))
      end
      instances.sort_by! { |i| [i[:status] == "waiting" ? 0 : 1, -Time.parse(i[:ts]).to_f] }

      wait_reasons = @db[:events]
                     .where(Sequel.like(:event, "wait.%"))
                     .select_group(:event, :tool)
                     .select_append { count.function.*.as(count) }
                     .select_append { max(ts).as(last_seen) }
                     .order(Sequel.desc(:count))
                     .all

      content_type :html
      erb :board, locals: { instances: instances, wait_reasons: wait_reasons }, layout: :layout
    end

    get "/board/:instance" do
      instance_name = params[:instance]

      events = @db[:events]
               .where(instance: instance_name)
               .order(Sequel.desc(:ts))
               .limit(50)
               .all

      content_type :html
      erb :instance, locals: { instance: instance_name, events: events }, layout: :layout
    end
  end
end
