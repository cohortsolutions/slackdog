require 'octokit'
require 'logger'

class GithubService
  class << self
    def client
      @client ||= Octokit::Client.new(access_token: ENV.fetch('GITHUB_TOKEN'))
    end

    def get_line(app, path, line)
      repo = repo_from_app(app)
      return if repo.nil? || repo.empty?

      contents = begin
        client.contents(repo, path: path, accept: 'application/vnd.github.v3.raw')
      rescue Octokit::NotFound => e
        return nil
      end

      index = line - 1
      lines = contents.split("\n")
      return unless index < lines.size

      {
        focus: lines[index].strip,
        context: lines[[0, index - 2].max..[index + 2, lines.size - 1].min]
      }
    end

    private

    def repo_from_app(app)
      app_key = "GITHUB_APPS_#{app.upcase.gsub('-', '_')}"
      ENV[app_key].tap do |value|
        logger.debug("Github mapping key '#{app_key}' not defined") if value.nil?
      end
    end

    def logger
      @logger ||= Logger.new(STDOUT)
    end
  end
end
