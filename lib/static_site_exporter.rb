# frozen_string_literal: true

require "fileutils"
require "nokogiri"
require "uri"

# Renders an explicit public route allowlist through Rails, without running a server.
# Output is a complete, new directory suitable for Cloudflare Pages Direct Upload.
# This command orchestrates a bounded export; keep its file operations together.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ClassLength
class StaticSiteExporter
  def initialize(output:, host:)
    @output = Pathname.new(output).expand_path
    @host = host
    raise ArgumentError, "Output already exists: #{@output}" if @output.exist?
    raise ArgumentError, "Host must be a DNS hostname" unless host.match?(/\A[a-z0-9.-]+\z/i)

    @session = ActionDispatch::Integration::Session.new(Rails.application)
    @session.host! host
    @session.https!
    @assets = []
    @pages = []
  end

  def export
    attack_enabled = Rack::Attack.enabled
    Rack::Attack.enabled = false
    Rails.cache.clear
    @output.mkpath
    html_routes.each { |route| export_html(route) }
    map_routes.each { |route| write_response("#{route}.json") }
    %w[/robots.txt /sitemap.xml].each { |route| write_response(route) }
    export_assets
    copy_public_files
    @output.join("_redirects").write(<<~RULES)
      /map /map/socials 302
      /sitemap /sitemap.xml 301
      /sitemap_index.xml /sitemap.xml 301
      /sitemaps.xml /sitemap.xml 301
      /sitemap.xml.gz /sitemap.xml 301
      /occasional / 302
    RULES
    @output.join("_headers").write(<<~RULES)
      /*
        X-Content-Type-Options: nosniff
      /assets/*
        Cache-Control: public, max-age=31536000, immutable
    RULES
    @output.join("export-manifest.json").write(JSON.pretty_generate(
                                                 generated_at: Time.current.iso8601, listing_day: SOLDNTime.today.iso8601,
                                                 host: @host, pages: @pages, map_data: map_routes.map { "#{it}.json" },
                                                 assets: @assets.uniq.sort
                                               ))
    @output
  rescue StandardError
    @output.join("EXPORT_FAILED").write("Do not publish this incomplete export") if @output.directory?
    raise
  ensure
    Rack::Attack.enabled = attack_enabled
  end

  private

  def map_routes
    @map_routes ||= ["/map/classes", "/map/socials"] +
                    (DAYNAMES + %w[today tomorrow]).map { "/map/classes/#{it}" } +
                    (SOLDNTime.listing_dates.map(&:iso8601) + %w[today tomorrow]).map { "/map/socials/#{it}" }
  end

  def html_routes
    %w[/ /about /listings_policy /privacy /name_clash] + map_routes
  end

  def get(route)
    @session.get(route)
    response = @session.response
    raise "Export #{route}: HTTP #{response.status}" unless response.status == 200

    response.body
  end

  def export_html(route)
    document = Nokogiri::HTML(get(route))
    document.css("meta[name^='csrf-']").remove
    document.css("link[rel='author']").each { it["href"] = "/humans.txt" }
    document.css("[src], [href]").each do |node|
      value = node["src"] || node["href"]
      @assets << value.split("?").first if value&.start_with?("/assets/")
    end
    map = document.at_css("[data-controller='map']")
    map["data-map-static-value"] = "true" if map
    # "/about" is written as about.html rather than about/index.html. Both are
    # served at the same URL by a static host, but only this one is served
    # *at* that URL: a host that finds about/index.html answers /about with a
    # redirect to /about/, which puts a redirect in front of every internal
    # link and every sitemap URL.
    filename = route == "/" ? "index.html" : "#{route.delete_prefix('/')}.html"
    write(filename, document.to_html)
    @pages << route
  end

  def write_response(route)
    write(route.delete_prefix("/"), get(route))
  end

  # Everything in public/ is meant to be served, so copy all of it. That
  # includes public/404.html, which is the styled error page Rails serves and a
  # static host serves too, so there is only one 404 to maintain; its single
  # dependency is /application_http_errors.css, which comes with it. The one
  # exception is .htaccess, which is Apache configuration and means nothing to a
  # static host.
  def copy_public_files
    Rails.public_path.children.each do |source|
      next if source.directory? || source.basename.to_s == ".htaccess"

      FileUtils.cp(source, @output.join(source.basename.to_s))
    end
  end

  def export_assets
    processed = []
    until (pending = @assets.uniq - processed).empty?
      pending.each do |asset|
        body = get(asset)
        write(asset.delete_prefix("/"), body)
        processed << asset
        next unless asset.end_with?(".css")

        body.scan(/url\(["']?([^\s)'" ]+)/).flatten.each do |url|
          next if url.start_with?("data:", "http:", "https:", "//", "#")

          path = URI.join("https://#{@host}#{asset}", url).path
          @assets << path if path.start_with?("/assets/")
        end
      end
    end
  end

  def write(filename, body)
    path = @output.join(filename)
    path.dirname.mkpath
    path.binwrite(body)
  end
end

# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/ClassLength
