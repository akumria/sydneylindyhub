# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaticPublicationWorker, :aggregate_failures do
  let(:runner) { instance_double(StaticPublicationRunner) }
  let(:worker) { described_class.new(runner:) }

  around do |example|
    ClimateControl.modify(STATIC_PUBLISH_ENABLED: "true") { example.run }
  end

  it "does nothing without queued work" do
    expect(worker.run_once).to be_nil
  end

  it "does not claim work while disabled" do
    publication = StaticPublication.create!(requested_by: "editor@example.com")
    ClimateControl.modify(STATIC_PUBLISH_ENABLED: "false") { worker.run_once }
    expect(publication.reload.status).to eq("queued")
  end

  it "marks a successful publication and records timestamps" do
    publication = StaticPublication.create!(requested_by: "editor@example.com")
    allow(runner).to receive(:call).with(publication) do
      expect(publication.reload.status).to eq("running")
      true
    end
    worker.run_once
    expect(publication.reload).to have_attributes(status: "succeeded", started_at: be_present, finished_at: be_present)
  end

  it "records an unsuccessful pipeline without retrying" do
    publication = StaticPublication.create!(requested_by: "editor@example.com")
    allow(runner).to receive(:call).and_return(false)
    worker.run_once
    expect(publication.reload.status).to eq("failed")
    expect(worker.run_once).to be_nil
  end

  it "records pipeline exceptions as failures" do
    publication = StaticPublication.create!(requested_by: "editor@example.com")
    allow(runner).to receive(:call).and_raise(IOError)
    worker.run_once
    expect(publication.reload.status).to eq("failed")
  end
end
