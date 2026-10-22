# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# Public pages are hosted separately. Rails must retain the editorial hostname;
# production host authorization is configured in config/environments/production.rb.

run Rails.application
Rails.application.load_server
