require 'octokit'

class GithubService
  APP_MAP = {
    'cohortflow' => 'cohortsolutions/cohortflow',
    'cohortpay-web' => 'cohortsolutions/cohortpay'
  }.freeze

  class << self
    def client
      @client ||= Octokit::Client.new(access_token: ENV.fetch('GITHUB_TOKEN'))
    end

    def get_line(app, path, line)
      repo = APP_MAP[app]
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
  end
end
