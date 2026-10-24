# frozen_string_literal: true

require "rails_helper"

RSpec.describe UrlHelpers do
  [nil, ""].each do |host|
    it "falls back to the public host when EDITORIAL_HOST is #{host.inspect}" do
      ClimateControl.modify(CANONICAL_HOST: "public.example.com", EDITORIAL_HOST: host) do
        expect(described_class.new.root_url).to eq("https://public.example.com/")
      end
    end
  end

  it "uses the editorial host for editorial URLs" do
    ClimateControl.modify(CANONICAL_HOST: "public.example.com", EDITORIAL_HOST: "edit.example.com") do
      expect(described_class.new.edit_external_event_url("token"))
        .to eq("https://edit.example.com/external_events/token/edit")
    end
  end
end
