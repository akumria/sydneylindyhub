# frozen_string_literal: true

require "rails_helper"

# The two ways the production cache has broken so far, neither of which this
# suite could otherwise see: the test environment sets :null_store, so no example
# exercises the store the app actually runs with, and no spec loads
# production.rb at all. Both failures were quiet - one took down every
# environment including development, the other returned nil and said nothing.
#
# These read the config files rather than booting them. Normally that is a
# smell, but the failures being guarded against are configuration failures, and
# booting production mode from a spec is not practical.
RSpec.describe "Production configuration" do
  # Rails provisions this, as it does the database and the host's own secrets.
  let(:host_provided) { %w[SECRET_KEY_BASE] }

  let(:documented) { Rails.root.join(".env.example").read.scan(/^\s*([A-Z_0-9]+)=/).flatten }

  let(:production_config) { Rails.root.join("config/environments/production.rb").read }

  let(:cache_store) { production_config[/config\.cache_store\s*=\s*:(\w+)/, 1] }

  # Rails evaluates the ERB in every section of a config file when it loads it,
  # not only the section for the current environment. So a bare ENV.fetch raises
  # in development and test as well: database.yml's production block used
  # ENV.fetch("DATABASE_URL") and took the whole app down locally until it was
  # changed to ENV["DATABASE_URL"].
  let(:unexplained) do
    required = %w[config/environments/production.rb config/database.yml].flat_map do |path|
      Rails.root.join(path).read.scan(/ENV\.fetch\(\s*["']([A-Z_0-9]+)["']\s*\)/).flatten
    end.uniq

    (required - host_provided - documented).map do |name|
      "#{name} is required at boot, is not host-provided, and is not in .env.example"
    end
  end

  it "only requires environment variables the host provides or .env.example documents" do
    expect(unexplained).to be_empty
  end

  # A memcached store with nothing listening returns nil on read and raises
  # nothing at all, so every request quietly re-rendered and the only symptom
  # was a site that felt slow. A local store cannot fail that way.
  it "uses a cache store that needs nothing provisioned separately" do
    expect(cache_store).to be_in(%w[memory_store solid_cache_store])
  end
end
