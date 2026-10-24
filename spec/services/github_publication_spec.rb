# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubPublication, :aggregate_failures do
  let(:publication) { StaticPublication.create!(requested_by: "editor@example.com") }
  let(:client) { described_class.new }
  let(:endpoint) { "https://api.github.com#{described_class::WORKFLOW}" }
  let(:title) { "Website publication #{publication.id}-#{publication.created_at.to_i}" }

  around do |example|
    ClimateControl.modify(GITHUB_ACTIONS_TOKEN: "test-token") { example.run }
  end

  def runs_response(run)
    stub_request(:get, %r{#{Regexp.escape(endpoint)}/runs\?}).to_return(
      body: JSON.generate(workflow_runs: [run]), status: 200
    )
  end

  it "dispatches only the fixed main workflow with a generated request identifier" do
    dispatch = stub_request(:post, "#{endpoint}/dispatches").with(
      headers: { "Authorization" => "Bearer test-token" },
      body: { ref: "main", inputs: { publication_id: "#{publication.id}-#{publication.created_at.to_i}" } }.to_json
    ).to_return(status: 204)
    client.dispatch(publication)
    expect(dispatch).to have_been_requested.once
  end

  it "accepts the newer dispatch response containing a run ID" do
    stub_request(:post, "#{endpoint}/dispatches").to_return(status: 200, body: '{"workflow_run_id":42}')
    expect { client.dispatch(publication) }.not_to raise_error
  end

  it "rejects explicit permission failures without exposing the response or token" do
    stub_request(:post, "#{endpoint}/dispatches").to_return(status: 403, body: "test-token")
    expect { client.dispatch(publication) }.to raise_error(described_class::Rejected, "GitHub rejected request (HTTP 403)")
  end

  it "preserves ambiguous server failures as unconfirmed" do
    stub_request(:post, "#{endpoint}/dispatches").to_return(status: 502)
    expect { client.dispatch(publication) }.to raise_error(described_class::Error, /could not be confirmed/)
  end

  it "treats a timeout as ambiguous without retrying the dispatch" do
    dispatch = stub_request(:post, "#{endpoint}/dispatches").to_timeout
    expect { client.dispatch(publication) }.to raise_error(described_class::Error, /could not be reached/)
    expect(dispatch).to have_been_requested.once
  end

  it "ignores other runs and retains a queued request while GitHub indexes it" do
    runs_response({ "id" => 42, "display_title" => "Publish static site", "status" => "completed" })
    expect(client.refresh(publication)).to be_nil
    expect(publication.reload.status).to eq("queued")
  end

  it "links a matching queued run without claiming it is running" do
    runs_response({ "id" => 42, "display_title" => title, "status" => "queued" })
    expect(client.refresh(publication)).to eq("#{described_class::RUNS}42")
    expect(publication.reload.status).to eq("queued")
  end

  it "records a running publication and preserves its start time on refresh" do
    runs_response({ "id" => 42, "display_title" => title, "status" => "in_progress" })
    client.refresh(publication)
    started = publication.reload.started_at
    client.refresh(publication)
    expect(publication.reload).to have_attributes(status: "running", started_at: started)
  end

  it "marks success only after the matched workflow completes successfully" do
    runs_response({ "id" => 42, "display_title" => title, "status" => "completed", "conclusion" => "success" })
    client.refresh(publication)
    expect(publication.reload).to have_attributes(status: "succeeded", finished_at: be_present)
  end

  it "records cancelled or failed workflows as unsuccessful publications" do
    runs_response({ "id" => 42, "display_title" => title, "status" => "completed", "conclusion" => "cancelled" })
    client.refresh(publication)
    expect(publication.reload.status).to eq("failed")
  end

  it "does not regress a completed publication if a run is subsequently rerun" do
    publication.update!(status: "succeeded")
    runs_response({ "id" => 42, "display_title" => title, "status" => "in_progress" })
    client.refresh(publication)
    expect(publication.reload.status).to eq("succeeded")
  end

  it "handles malformed API responses without changing the request" do
    stub_request(:get, %r{#{Regexp.escape(endpoint)}/runs\?}).to_return(body: "not json")
    expect { client.refresh(publication) }.to raise_error(described_class::Error, /Invalid/)
    expect(publication.reload.status).to eq("queued")
  end
end
