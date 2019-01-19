require 'octokit'

class GithubService
  class << self
    def client
      @client ||= Octokit::Client.new(access_token: ENV.fetch('GITHUB_TOKEN'))
    end

    def get_line(app, path, line)
      repo = repo_from_app(app)
      return unless repo

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
      repo = ENV["GITHUB_APPS_#{app.upcase.gsub('-', '_')}"]
      return repo unless repo.empty?
    end
  end
end
