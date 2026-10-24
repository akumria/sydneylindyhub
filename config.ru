# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# An optional editorial host is the canonical host for this Rails application.
rails_host = ENV.fetch("EDITORIAL_HOST", nil).presence || ENV.fetch("CANONICAL_HOST", nil)
use Rack::CanonicalHost, rails_host if Rails.env.production? && rails_host

run Rails.application
Rails.application.load_server
