# frozen_string_literal: true

require "yaml"

module Brivlo
  # Loads configuration from ~/.brivlo.yml, with ENV overrides.
  module Config
    CONFIG_FILE = File.join(Dir.home, ".brivlo.yml")

    def self.load
      file_config = File.exist?(CONFIG_FILE) ? YAML.load_file(CONFIG_FILE) : {}

      file_config.each do |key, value|
        ENV[key] ||= value.to_s
      end

      file_config
    end

    def self.fetch(key, default = nil)
      ENV.fetch(key, default)
    end
  end
end
