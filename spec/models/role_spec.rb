# frozen_string_literal: true

require "rails_helper"
require "support/shoulda_matchers"

RSpec.describe Role do
  describe "Validations" do
    subject { build(:role) }

    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to allow_value("editor@example.com").for(:email) }
    it { is_expected.not_to allow_value("not-an-email").for(:email) }
    it { is_expected.to validate_presence_of(:role) }
  end

  describe "#role" do
    it "is an enum" do
      expect(described_class.new).to define_enum_for(:role)
        .with_values("admin" => "admin", "editor" => "editor")
        .backed_by_column_of_type(:string)
    end
  end
end
