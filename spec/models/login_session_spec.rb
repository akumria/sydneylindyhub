# frozen_string_literal: true

require "spec_helper"
require "app/models/login_session"
require "active_support"
require "active_support/core_ext/object/blank"

RSpec.describe LoginSession do
  describe "log_in!" do
    it "resets the session and stores only the editor identity", :aggregate_failures do
      session = {}
      request = instance_double("ActionDispatch::Request", session:, reset_session: true)
      logger = instance_double("Logger", info: true)

      described_class.new(request, role_finder: double, logger:).log_in!(
        email: "editor@example.com",
        name: "Willa Mae Ricker"
      )

      expect(request).to have_received(:reset_session)
      expect(session[:user]).to eq("email" => "editor@example.com", "name" => "Willa Mae Ricker")
      expect(logger).to have_received(:info).with("Logged in as editor@example.com")
    end
  end

  describe "log_out!" do
    it "resets the session and records the email in the log", :aggregate_failures do
      session = { user: { "email" => "editor@example.com", "name" => "Editor" } }
      request = instance_double("ActionDispatch::Request", session:, reset_session: true)
      logger = instance_double("Logger", info: true)

      described_class.new(request, role_finder: double, logger:).log_out!

      expect(request).to have_received(:reset_session)
      expect(logger).to have_received(:info).with("Logged out as editor@example.com")
    end
  end

  describe "#user" do
    it "is logged in while its approved role exists" do
      session = { user: { "email" => "editor@example.com", "name" => "Editor" } }
      request = instance_double("ActionDispatch::Request", session:)
      role = instance_double("Role", admin?: true)
      role_finder = class_double("Role", find_by: role)

      user = described_class.new(request, role_finder:, logger: double).user

      expect(user).to have_attributes(
        logged_in?: true,
        admin?: true,
        email: "editor@example.com",
        auth_id: "editor@example.com",
        name: "Editor",
        name_with_role: "Editor (Admin)"
      )
    end

    it "is logged out after its approved role is removed", :aggregate_failures do
      session = { user: { "email" => "former@example.com", "name" => "Former editor" } }
      request = instance_double("ActionDispatch::Request", session:)
      role_finder = class_double("Role", find_by: nil)

      user = described_class.new(request, role_finder:, logger: double).user

      expect(user.logged_in?).to be false
      expect(user.admin?).to be false
    end

    it "returns a guest for an empty session" do
      request = instance_double("ActionDispatch::Request", session: {})

      user = described_class.new(request, role_finder: double, logger: double).user

      expect(user).to have_attributes(
        logged_in?: false,
        admin?: false,
        email: "NO EMAIL",
        auth_id: "NO EMAIL",
        name: "Guest",
        name_with_role: "Guest"
      )
    end
  end
end
