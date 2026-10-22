# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "static_site_exporter"

RSpec.describe StaticSiteExporter do
  # One export exercises the complete publishable artifact, including its dependent files.
  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
  it "exports public navigation and map data without editor pages or CSRF tokens" do
    Dir.mktmpdir do |directory|
      output = Pathname.new(directory).join("site")
      exporter = described_class.new(output:, host: "www.sydneylindyhub.com")
      # Exercise CSS dependencies as well as assets referenced directly by HTML.
      allow(exporter).to receive(:get).and_wrap_original do |original, path|
        next "<svg xmlns='http://www.w3.org/2000/svg'/>" if path == "/assets/dependency.svg"

        body = original.call(path)
        dependency_rule = ".test { background: url(dependency.svg); mask: url(data:image/png;base64,AA); }"
        path.end_with?(".css") ? "#{body}\n#{dependency_rule}" : body
      end
      ClimateControl.modify CANONICAL_HOST: "www.sydneylindyhub.com" do
        exporter.export
      end
      manifest = JSON.parse(output.join("export-manifest.json").read)
      expect(manifest.fetch("pages")).to include("/", "/privacy", "/map/classes/Monday", "/map/socials/today")
      expect(output.join("login")).not_to exist
      expect(output.join("admin")).not_to exist
      expect(output.join("privacy.html").read).not_to include("csrf-token")
      expect(output.join("map/classes.html").read).to include('data-map-static-value="true"')
      manifest.fetch("map_data").each do |path|
        expect(JSON.parse(output.join(path.delete_prefix("/")).read)).to have_key("markers")
      end
      manifest.fetch("assets").each do |path|
        expect(output.join(path.delete_prefix("/"))).to exist
      end
    end
  end

  it "marks an incomplete export and restores throttling when rendering fails" do
    Dir.mktmpdir do |directory|
      output = Pathname.new(directory).join("site")
      exporter = described_class.new(output:, host: "example.com")
      allow(exporter).to receive(:html_routes).and_return(["/missing-public-page"])
      expect { exporter.export }.to raise_error(/HTTP 404/)
      expect(output.join("EXPORT_FAILED")).to exist
      expect(Rack::Attack.enabled).to be true
    end
  end

  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

  it "refuses to overwrite an existing directory" do
    Dir.mktmpdir do |directory|
      expect { described_class.new(output: directory, host: "example.com") }.to raise_error(ArgumentError, /already exists/)
    end
  end
end
