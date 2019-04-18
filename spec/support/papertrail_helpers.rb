require './papertrail'

module PapertrailHelpers
  def disable_papertrail!
    allow(Papertrail).to receive(:log_lines_between) { raise 'Papertrail called, but not stubbed' }
  end

  def stub_papertrail(file)
    allow(Papertrail).to receive(:log_lines_between).and_return(File.readlines(file))
  end
end
