# frozen_string_literal: true

require_relative 'base'

module Templates
  class Ingress < Base
    NAME = 'ingress'

    def manifest
      hosts.each_with_index.map do |host, i|
        {
          'op' => 'replace',
          'path' => "/spec/rules/#{i}/host",
          'value' => [namespace, host].join('.')
        }
      end
    end

    private

    def hosts
      options[:hosts] || []
    end
  end
end
