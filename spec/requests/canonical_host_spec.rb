# frozen_string_literal: true

require "rails_helper"
require "rack/canonical_host"

RSpec.describe "Canonical Rails host" do
  def redirect_for(editorial_host)
    ClimateControl.modify(CANONICAL_HOST: "public.example.com", EDITORIAL_HOST: editorial_host) do
      allow(Rails.env).to receive(:production?).and_return(true)
      app = Rack::Builder.parse_file(Rails.root.join("config.ru").to_s)
      Rack::MockRequest.new(app).get("https://alias.example.com/login?from=mail")
    end
  end

  it "redirects aliases to the editorial host, preserving the path and query" do
    expect(redirect_for("edit.example.com")["location"])
      .to eq("https://edit.example.com/login?from=mail")
  end

  it "serves login on the editorial host without redirecting it to the public site" do
    ClimateControl.modify(CANONICAL_HOST: "public.example.com", EDITORIAL_HOST: "edit.example.com") do
      allow(Rails.env).to receive(:production?).and_return(true)
      app = Rack::Builder.parse_file(Rails.root.join("config.ru").to_s)

      expect(Rack::MockRequest.new(app).get("https://edit.example.com/login").status).to eq(200)
    end
  end

  [nil, ""].each do |host|
    it "retains public canonical redirects when EDITORIAL_HOST is #{host.inspect}" do
      expect(redirect_for(host)["location"])
        .to eq("https://public.example.com/login?from=mail")
    end
  end
end
