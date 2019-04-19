require './papertrail'

module PapertrailHelpers
  def disable_papertrail!
    allow(PapertrailService).to receive(:log_lines_between) { raise 'PapertrailService called, but not stubbed' }
  end

  def stub_papertrail(file)
    allow(PapertrailService).to receive(:log_lines_between).and_return(File.readlines(file))
  end
end
