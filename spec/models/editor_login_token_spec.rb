# frozen_string_literal: true

require "rails_helper"
require "timecop"

RSpec.describe EditorLoginToken do
  it "round-trips an approved role" do
    role = create(:editor)

    expect(described_class.role_for(described_class.generate(role))).to eq(role)
  end

  it "rejects a changed token" do
    role = create(:editor)
    token = described_class.generate(role)

    expect(described_class.role_for("#{token}changed")).to be_nil
  end

  it "rejects an expired token" do
    role = create(:editor)
    token = described_class.generate(role)

    Timecop.travel(16.minutes.from_now) do
      expect(described_class.role_for(token)).to be_nil
    end
  end
end
