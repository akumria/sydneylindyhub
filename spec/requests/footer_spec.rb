# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The site footer" do
  it "does not credit the upstream author on the Sydney site" do
    get "/"

    aggregate_failures do
      expect(response.body).to include("Maintained by volunteers")
      expect(response.body).not_to include("@dgmstuart")
    end
  end

  it "keeps the upstream credit on the London site" do
    stub_const("CITY", City.build_london)

    get "/"

    expect(response.body).to include("@dgmstuart")
  end

  it "links the credit to the contact page" do
    get "/"

    expect(response.body).to include(%(href="/about"))
  end
end
