# frozen_string_literal: true

require "rails_helper"

RSpec.describe NumericStringValidator, :aggregate_failures do
  let(:model_class) do
    Class.new do
      include ActiveModel::Model

      attr_accessor :code

      def self.name
        "NumericCode"
      end
    end
  end

  it "accepts a string containing only digits" do
    model_class.validates :code, numeric_string: true
    record = model_class.new(code: "00123")

    expect(record).to be_valid
  end

  it "rejects non-digit characters with the default message" do
    model_class.validates :code, numeric_string: true
    record = model_class.new(code: "12a")

    expect(record).not_to be_valid
    expect(record.errors[:code]).to eq(["must contain only digits"])
  end

  it "rejects an empty string" do
    model_class.validates :code, numeric_string: true

    expect(model_class.new(code: "")).not_to be_valid
  end

  it "honours a custom pattern and message" do
    model_class.validates :code, numeric_string: { with: /\A[0-9]{2}\z/, message: :invalid }
    record = model_class.new(code: "123")

    expect(record).not_to be_valid
    expect(record.errors[:code]).to eq(["is invalid"])
  end
end
