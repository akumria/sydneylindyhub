# frozen_string_literal: true

require "net/http"
require "json"

# Only this repository's fixed production workflow can be dispatched.
class GithubPublication
  WORKFLOW = "/repos/akumria/sydneylindyhub/actions/workflows/publish-static-site.yml"
  RUNS = "https://github.com/akumria/sydneylindyhub/actions/runs/"
  Error = Class.new(StandardError)
  Rejected = Class.new(Error)

  def self.configured?
    ENV["GITHUB_ACTIONS_TOKEN"].present?
  end

  def dispatch(publication)
    request("#{WORKFLOW}/dispatches", payload: {
              ref: "main", inputs: { publication_id: key(publication) }
            })
  end

  def refresh(publication)
    run = matching_run(publication)
    return unless run

    update(publication, run) if publication.status.in?(%w[queued running])
    "#{RUNS}#{Integer(run.fetch('id'))}"
  rescue JSON::ParserError, KeyError, ArgumentError, TypeError
    raise Error, "Invalid GitHub workflow response"
  end

  private

  def key(publication)
    "#{publication.id}-#{publication.created_at.to_i}"
  end

  def update(publication, run)
    if run.fetch("status") == "completed"
      publication.update!(status: run["conclusion"] == "success" ? "succeeded" : "failed", finished_at: Time.current)
    elsif run["status"] == "in_progress"
      publication.update!(status: "running", started_at: publication.started_at || Time.current)
    end
  end

  def matching_run(publication)
    query = URI.encode_www_form(branch: "main", event: "workflow_dispatch", per_page: 100,
                                created: ">=#{(publication.created_at - 1.minute).utc.iso8601}")
    runs = JSON.parse(request("#{WORKFLOW}/runs?#{query}")).fetch("workflow_runs")
    runs.find { |candidate| candidate["display_title"] == "Website publication #{key(publication)}" }
  end

  def request(path, payload: nil)
    uri = URI("https://api.github.com#{path}")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.request(message(uri, payload))
    end
    response_body(response)
  rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError
    raise Error, "GitHub could not be reached"
  end

  def message(uri, payload)
    headers = { "Authorization" => "Bearer #{ENV.fetch('GITHUB_ACTIONS_TOKEN')}",
                "Accept" => "application/vnd.github+json", "X-GitHub-Api-Version" => "2026-03-10",
                "Content-Type" => "application/json" }
    message = payload ? Net::HTTP::Post.new(uri, headers) : Net::HTTP::Get.new(uri, headers)
    message.body = JSON.generate(payload) if payload
    message
  end

  def response_body(response)
    return response.body if response.is_a?(Net::HTTPSuccess)

    raise Rejected, "GitHub rejected request (HTTP #{response.code})" if response.code.start_with?("4")

    raise Error, "GitHub response could not be confirmed"
  end
end
