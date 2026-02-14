# frozen_string_literal: true

require "spec_helper"
require "brivlo/card_resolver"

RSpec.describe Brivlo::CardResolver do
  describe ".resolve" do
    let(:trello_output) do
      "Fix login timeout\nURL: https://trello.com/c/abc123\n\nLabels: bug\n"
    end

    it "returns card_title and card_url" do
      allow(described_class).to receive(:run_trello).and_return(trello_output)

      result = described_class.resolve("#42")

      expect(result).to eq({ card_title: "Fix login timeout", card_url: "https://trello.com/c/abc123" })
    end

    it "returns nil when trello command fails" do
      allow(described_class).to receive(:run_trello).and_return(nil)

      result = described_class.resolve("#42")

      expect(result).to be_nil
    end

    it "returns nil when output has no URL line" do
      allow(described_class).to receive(:run_trello).and_return("Just a title\n")

      result = described_class.resolve("#42")

      expect(result).to be_nil
    end
  end

  describe ".extract_card_ref" do
    it "extracts ref from 'bin/trello card show <ref>'" do
      expect(described_class.extract_card_ref("bin/trello card show #42")).to eq("#42")
    end

    it "extracts ref with shortlink" do
      expect(described_class.extract_card_ref("bin/trello card show abc123XY")).to eq("abc123XY")
    end

    it "returns nil for non-matching summaries" do
      expect(described_class.extract_card_ref("bundle exec rspec")).to be_nil
    end

    it "returns nil for nil input" do
      expect(described_class.extract_card_ref(nil)).to be_nil
    end
  end

  describe ".extract_done_ref" do
    it "extracts ref from 'bin/trello card move <ref> Done/Committed'" do
      result = described_class.extract_done_ref('bin/trello card move #42 "Done/Committed"')

      expect(result).to eq("#42")
    end

    it "extracts ref from 'bin/trello card move <ref> Done/Deployed'" do
      result = described_class.extract_done_ref('bin/trello card move abc123 "Done/Deployed"')

      expect(result).to eq("abc123")
    end

    it "returns nil for moves to non-Done lists" do
      result = described_class.extract_done_ref('bin/trello card move #42 "In Progress"')

      expect(result).to be_nil
    end

    it "returns nil for non-matching summaries" do
      expect(described_class.extract_done_ref("bundle exec rspec")).to be_nil
    end
  end
end
