require './formatters/attachment_formatter'

class RequestAttachmentFormatter < AttachmentFormatter
  protected

  def request_event_text(show_ip: false)
    request = event.request
    return unless request

    text = ''

    if request['path']
      path = request['path'].split('?', 2).first
      path = "#{path[0..4]}...#{path[-35..-1]}" if path.size > 43 # 5 + 35 + 3 (for ...)
      text << "`[#{request['method']}]` #{path}"
    end

    redirected = request['redirected_to']
    redirection_prompt = if filter_chain_redirected_by = request['filter_chain_redirected_by']
      "_redirected by #{filter_chain_redirected_by}_"
    elsif redirected
      '_redirected_'
    end

    if redirection_prompt
      margin = [redirection_prompt.size, 35].min
      text << " *->* <#{redirected}|#{redirection_prompt.ljust(margin)}>"
    end

    if show_ip && ip = event.request['ip']
      text << " (#{ip})"
    end

    text
  end
end
