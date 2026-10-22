# frozen_string_literal: true

desc "Export public HTML, map JSON and assets to a NEW directory (OUTPUT, CANONICAL_HOST required)"
task "static_site:export" => :environment do
  require "static_site_exporter"
  output = StaticSiteExporter.new(output: ENV.fetch("OUTPUT"), host: ENV.fetch("CANONICAL_HOST")).export
  puts "Static site exported to #{output}"
end

desc "Run the database-backed static publication worker (requires STATIC_PUBLISH_ENABLED=true)"
task "static_site:publication_worker" => :environment do
  abort "Set STATIC_PUBLISH_ENABLED=true to run the publication worker" unless StaticPublication.enabled?

  loop do
    StaticPublicationWorker.new.run_once
    sleep 2
  end
end
