# frozen_string_literal: true

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

    get "/ping" do
      "ok"
    end
  end
end
