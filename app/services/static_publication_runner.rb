# frozen_string_literal: true

require "timeout"

# Runs only the fixed, validated publication pipeline; no editor input becomes a command.
class StaticPublicationRunner
  def call(publication)
    output = Rails.root.join("tmp", "static-publication-#{publication.id}").to_s
    log_path = Rails.root.join("log", "static-publication-#{publication.id}.log")
    File.open(log_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |log|
      run(output, log)
    end
  end

  private

  def run(output, log)
    pid = Process.spawn({ "OUTPUT" => output }, Rails.root.join("bin/publish-static-site").to_s,
                        "--deploy", out: log, err: log, pgroup: true, chdir: Rails.root.to_s)
    _, status = Timeout.timeout(600) { Process.wait2(pid) }
    completed = true
    status.success?
  ensure
    stop(pid) unless completed || pid.nil?
  end

  def stop(pid)
    begin
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
      # The subprocess may already have exited.
    end
    Process.wait(pid)
  end
end
