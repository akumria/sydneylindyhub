# frozen_string_literal: true

require "spec_helper"
require "app/presenters/users_listing"

RSpec.describe UsersListing do
  describe "#users" do
    it "returns a list of users" do
      roles = [instance_double("Role", id: 23, email: "mildred@example.com", name: "Mildred Pollard", admin?: false)]
      listing = described_class.new(roles:, current_user_id: "someone@example.com")

      results = listing.users

      expect(results.first).to have_attributes(
        id: 23,
        admin?: false,
        current?: false,
        name: "Mildred Pollard",
        email: "mildred@example.com"
      )
    end

    it "identifies the current user" do
      roles = [instance_double("Role", id: 17, email: "freida@example.com", name: "Freida Washington", admin?: true)]
      listing = described_class.new(roles:, current_user_id: "freida@example.com")

      results = listing.users

      expect(results.first).to have_attributes(
        id: 17,
        admin?: true,
        current?: true,
        name: "Freida Washington",
        email: "freida@example.com"
      )
    end
  end
end
