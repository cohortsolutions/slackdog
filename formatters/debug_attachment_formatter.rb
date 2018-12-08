require './formatters/attachment_formatter'

class DebugAttachmentFormatter < AttachmentFormatter
  def to_payload
    debug_info = event.debug_info
    return unless debug_info

    fields = []
    dynos = debug_info['dynos']
    addons = debug_info['addons']
    memory = debug_info['memory']

    if cpu_log = dynos && dynos.detect { |l| l['fields'].key?('load_avg_1m') }
      meta = cpu_log['fields']
      fields << {
        'title' => 'Server Load',
        'short' => true,
        'value' => [
          meta['load_avg_1m'],
          meta['load_avg_5m'],
          meta['load_avg_15m']
        ].join(' ')
      }
    end if dynos

    if ram_log = dynos && dynos.detect { |l| l['fields'].key?('memory_quota') }
      meta = ram_log['fields']
      fields << {
        'title' => 'Memory Usage',
        'short' => true,
        'value' => "#{meta['memory_total']} / #{meta['memory_quota']}"
      }
    end

    if db_size_log = addons && addons.detect { |l| l['fields'].key?('db_size') }
      meta = db_size_log['fields']

      fields << {
        'title' => 'Database size',
        'short' => true,
        'value' => "#{meta['db_size']} (#{meta['tables']} tables)"
      }

      fields << {
        'title' => 'Database connections',
        'short' => true,
        'value' => "#{meta['active-connections']} active. #{meta['waiting-connections']} waiting."
      }

      fields << {
        'title' => 'Database memory',
        'short' => true,
        'value' => "#{meta['memory-total']} available. #{meta['memory-free']} free."
      }
    end

    {}.tap do |attachment|
      attachment['fields'] = fields
      attachment['mrkdwn_in'] = ['pretext', 'fields']
      attachment['pretext'] = "*#{event.app}* > #{event.process}"
    end
  end
end
