# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationMailer do
  it "uses the editorial host without inheriting a development port" do
    ClimateControl.modify(EDITORIAL_HOST: "edit.example.com") do
      expect(described_class.new.default_url_options)
        .to eq(host: "edit.example.com", protocol: "https")
    end
  end

  it "preserves configured mailer defaults when no editorial host is set" do
    ClimateControl.modify(EDITORIAL_HOST: nil) do
      expect(described_class.new.default_url_options).to eq(ActionMailer::Base.default_url_options)
    end
  end
end
