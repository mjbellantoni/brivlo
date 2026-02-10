# frozen_string_literal: true

require "sequel"

module Brivlo
  # Creates and connects to the SQLite database used for event storage.
  module Database
    def self.setup(db) # rubocop:disable Metrics/MethodLength
      db.create_table?(:events) do
        String :event_id, primary_key: true
        String :ts, null: false
        String :event, null: false
        String :instance, null: false
        String :host, null: false
        String :card
        String :skill
        String :tool
        String :summary
        String :meta
        String :received_at, null: false
      end

      db.create_table?(:dismissed_instances) do
        String :instance, primary_key: true
        String :dismissed_at, null: false
      end
    end

    def self.connect(path = nil)
      path ||= File.join(Dir.pwd, "db", "brivlo.sqlite3")
      FileUtils.mkdir_p(File.dirname(path))
      db = Sequel.sqlite(path)
      setup(db)
      db
    end
  end
end
