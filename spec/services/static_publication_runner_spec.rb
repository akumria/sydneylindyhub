# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe StaticPublicationRunner, :aggregate_failures do
  let(:root) { Pathname.new(Dir.mktmpdir("static-publication-spec-")) }
  let(:publication) { instance_double(StaticPublication, id: 17) }

  before do
    FileUtils.mkdir_p(root.join("bin"))
    FileUtils.mkdir_p(root.join("log"))
    allow(Rails).to receive(:root).and_return(root)
  end

  after { FileUtils.remove_entry(root) }

  def script(body)
    path = root.join("bin/publish-static-site")
    path.write("#!/bin/sh\n#{body}\n")
    path.chmod(0o700)
  end

  it "executes the fixed deployment pipeline and keeps logs private" do
    script('echo "$1 $OUTPUT"')
    expect(described_class.new.call(publication)).to be(true)
    log = root.join("log/static-publication-17.log")
    expect(log.read).to include("--deploy", "tmp/static-publication-17")
    expect(log.stat.mode & 0o777).to eq(0o600)
  end

  it "reports unsuccessful execution" do
    script("exit 1")
    expect(described_class.new.call(publication)).to be(false)
  end

  it "kills and reaps the process group when execution times out" do
    script("sleep 30")
    allow(Timeout).to receive(:timeout).with(600).and_raise(Timeout::Error)
    expect { described_class.new.call(publication) }.to raise_error(Timeout::Error)
  end

  it "does not overwrite existing private logs" do
    root.join("log/static-publication-17.log").write("previous")
    expect { described_class.new.call(publication) }.to raise_error(Errno::EEXIST)
  end

  it "handles an already exited process during timeout cleanup" do
    script("exit 0")
    allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
    allow(Process).to receive(:kill).and_raise(Errno::ESRCH)
    expect { described_class.new.call(publication) }.to raise_error(Timeout::Error)
  end

  it "propagates failure to start the pipeline" do
    expect { described_class.new.call(publication) }.to raise_error(Errno::ENOENT)
  end
end
