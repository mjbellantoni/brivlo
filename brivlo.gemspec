# frozen_string_literal: true

require_relative "lib/brivlo/version"

Gem::Specification.new do |spec|
  spec.name = "brivlo"
  spec.version = Brivlo::VERSION
  spec.authors = ["Matthew Bellantoni"]
  spec.email = ["mjbellantoni@gmail.com"]

  spec.summary = "Tiny control plane for monitoring Claude Code instances"
  spec.description = "Stores and displays events from multiple Claude instances across hosts"
  spec.homepage = "https://github.com/mjbellantoni/brivlo"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "bin"
  spec.executables = %w[brivlo_event brivlo_server]
  spec.require_paths = ["lib"]

  spec.add_dependency "rackup", "~> 2.0"
  spec.add_dependency "sequel", "~> 5.0"
  spec.add_dependency "sinatra", "~> 4.0"
  spec.add_dependency "sqlite3", "~> 2.0"
  spec.add_dependency "webrick", "~> 1.8"
end
