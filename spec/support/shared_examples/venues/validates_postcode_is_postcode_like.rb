# frozen_string_literal: true

RSpec.shared_examples "validates postcode is postcode-like" do |model_name|
  it "is valid with no postcode" do
    model = build(model_name, postcode: nil)
    model.valid?
    expect(model.errors.messages[:postcode]).to be_empty
  end

  it "is valid with a Sydney postcode" do
    model = build(model_name, postcode: "2000")
    model.valid?
    expect(model.errors.messages[:postcode]).to be_empty
  end

  it "is valid with a postcode that starts with zero" do
    model = build(model_name, postcode: "0800")
    model.valid?
    expect(model.errors.messages[:postcode]).to be_empty
  end

  it "is invalid with something of the same length that isn't a postcode" do
    model = build(model_name, postcode: "2OOO")
    model.valid?
    expect(model.errors.messages[:postcode]).to contain_exactly("is not a valid postcode")
  end

  it "is invalid with something which is too long" do
    model = build(model_name, postcode: "20000")
    model.valid?
    expect(model.errors.messages[:postcode]).to contain_exactly("is not a valid postcode")
  end
end
