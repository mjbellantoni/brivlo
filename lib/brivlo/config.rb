# frozen_string_literal: true

require "socket"
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

      ENV["BRIVLO_INSTANCE"] ||= File.basename(Dir.pwd)
      ENV["BRIVLO_HOST"] ||= sanitize_hostname(Socket.gethostname)

      file_config
    end

    def self.sanitize_hostname(name)
      name.end_with?(".local") ? "local" : name
    end

    def self.fetch(key, default = nil)
      ENV.fetch(key, default)
    end
  end
end
