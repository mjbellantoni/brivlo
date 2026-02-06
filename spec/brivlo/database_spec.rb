# frozen_string_literal: true

require "spec_helper"
require "brivlo/database"

RSpec.describe Brivlo::Database do
  let(:db) { Sequel.sqlite }

  describe ".setup" do
    it "creates the events table" do
      described_class.setup(db)

      expect(db.tables).to include(:events)
    end

    it "is idempotent" do
      described_class.setup(db)
      described_class.setup(db)

      expect(db.tables).to include(:events)
    end

    it "creates all expected columns" do
      described_class.setup(db)

      columns = db.schema(:events).map(&:first)
      expect(columns).to eq(%i[event_id ts event instance host card skill tool summary meta received_at])
    end
  end
end
