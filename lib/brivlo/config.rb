# frozen_string_literal: true

require "yaml"

module Brivlo
  # Loads configuration from .brivlo.yml (project, then home), with ENV overrides.
  module Config
    CONFIG_FILES = [
      File.join(Dir.pwd, ".brivlo.yml"),
      File.join(Dir.home, ".brivlo.yml")
    ].freeze

    def self.load
      path = CONFIG_FILES.find { |p| File.exist?(p) }
      file_config = path ? YAML.load_file(path) : {}

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
