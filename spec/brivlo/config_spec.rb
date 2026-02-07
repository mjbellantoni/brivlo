# frozen_string_literal: true

require "spec_helper"
require "brivlo/config"

RSpec.describe Brivlo::Config do
  describe ".load" do
    it "loads values from config file" do
      allow(File).to receive(:exist?).and_return(true)
      allow(YAML).to receive(:load_file).and_return("BRIVLO_TOKEN" => "from-file")
      allow(ENV).to receive(:[]=)

      described_class.load

      expect(ENV).to have_received(:[]=).with("BRIVLO_TOKEN", "from-file")
    end

    it "does not override existing env vars" do
      allow(File).to receive(:exist?).and_return(true)
      allow(YAML).to receive(:load_file).and_return("BRIVLO_TOKEN" => "from-file")

      ENV["BRIVLO_TOKEN"] = "from-env"
      described_class.load

      expect(ENV["BRIVLO_TOKEN"]).to eq("from-env")
    ensure
      ENV.delete("BRIVLO_TOKEN")
    end

    it "returns empty hash when config file does not exist" do
      allow(File).to receive(:exist?).and_return(false)

      result = described_class.load

      expect(result).to eq({})
    end
  end

  describe ".fetch" do
    it "returns env var value" do
      ENV["BRIVLO_TEST_KEY"] = "test-value"

      expect(described_class.fetch("BRIVLO_TEST_KEY")).to eq("test-value")
    ensure
      ENV.delete("BRIVLO_TEST_KEY")
    end

    it "returns default when key is not set" do
      expect(described_class.fetch("BRIVLO_NONEXISTENT", "fallback")).to eq("fallback")
    end

    it "returns nil when key is not set and no default" do
      expect(described_class.fetch("BRIVLO_NONEXISTENT")).to be_nil
    end
  end
end
