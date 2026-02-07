# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require "json"
require "brivlo/client"

RSpec.describe Brivlo::Client do
  let(:endpoint) { "http://localhost:9292" }
  let(:token) { "test-token" }

  before do
    allow(Brivlo::Config).to receive(:fetch).and_call_original
    allow(Brivlo::Config).to receive(:fetch).with("BRIVLO_ENDPOINT").and_return(endpoint)
    allow(Brivlo::Config).to receive(:fetch).with("BRIVLO_TOKEN").and_return(token)
  end

  describe "#send_event" do
    it "posts JSON to the endpoint" do
      stub = stub_request(:post, "#{endpoint}/events")
             .with(
               headers: {
                 "Content-Type" => "application/json",
                 "Authorization" => "Bearer #{token}"
               }
             )
             .to_return(status: 201, body: "ok")

      client = described_class.new
      client.send_event(
        event: "wait.permission",
        instance: "wt-a",
        host: "mjb-dev-01"
      )

      expect(stub).to have_been_requested
    end

    it "includes event_id and ts in payload" do
      stub_request(:post, "#{endpoint}/events").to_return(status: 201)

      client = described_class.new
      client.send_event(event: "task.start", instance: "wt-a", host: "dev-01")

      expect(WebMock).to(have_requested(:post, "#{endpoint}/events")
        .with do |req|
          body = JSON.parse(req.body)
          body["event_id"] =~ /\A[0-9a-f-]{36}\z/ && body["ts"] =~ /\d{4}-\d{2}-\d{2}T/
        end)
    end

    it "includes optional fields in payload" do
      stub_request(:post, "#{endpoint}/events").to_return(status: 201)

      client = described_class.new
      client.send_event(
        event: "wait.permission",
        instance: "wt-a",
        host: "dev-01",
        card: "123",
        skill: "brainstorming",
        tool: "Bash",
        summary: "Needs approval",
        meta: { "foo" => "bar" }
      )

      expect(WebMock).to(have_requested(:post, "#{endpoint}/events")
        .with do |req|
          body = JSON.parse(req.body)
          body["card"] == "123" &&
            body["tool"] == "Bash" &&
            body["meta"] == '{"foo":"bar"}'
        end)
    end

    it "no-ops silently when BRIVLO_ENDPOINT is not set" do
      allow(Brivlo::Config).to receive(:fetch).with("BRIVLO_ENDPOINT").and_return(nil)

      client = described_class.new

      expect { client.send_event(event: "task.start", instance: "wt-a", host: "dev") }
        .not_to raise_error
    end

    it "warns to stderr and exits cleanly on connection failure" do
      stub_request(:post, "#{endpoint}/events").to_raise(Errno::ECONNREFUSED)

      client = described_class.new

      expect { client.send_event(event: "task.start", instance: "wt-a", host: "dev") }
        .to output(/brivlo/i).to_stderr
    end

    it "warns to stderr and exits cleanly on timeout" do
      stub_request(:post, "#{endpoint}/events").to_timeout

      client = described_class.new

      expect { client.send_event(event: "task.start", instance: "wt-a", host: "dev") }
        .to output(/brivlo/i).to_stderr
    end

    it "warns when BRIVLO_TOKEN is not set" do
      allow(Brivlo::Config).to receive(:fetch).with("BRIVLO_TOKEN").and_return(nil)

      client = described_class.new

      expect { client.send_event(event: "task.start", instance: "wt-a", host: "dev") }
        .to output(/BRIVLO_TOKEN/i).to_stderr
    end
  end
end
