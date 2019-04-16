module GithubHelpers
  def stub_github(repo, file)
    stub_request(:get, "https://api.github.com/repos/#{repo}/contents/#{file}").
      with(headers: {
        'Accept' => 'application/vnd.github.v3.raw',
        'Authorization' => "token #{ENV['GITHUB_TOKEN']}",
        'Content-Type' => 'application/json'
      }).
      to_return(body: File.read("./spec/fixtures/files/#{file}"))
  end
end