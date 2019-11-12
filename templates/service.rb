# frozen_string_literal: true

require_relative 'base'

module Templates
  class Service < Base
    NAME = 'service'

    def manifest
      {
        'kind' => 'Service',
        'apiVersion' => 'v1',
        'metadata' => {
          'name' => service
        },
        'spec' => {
          'type' => 'ExternalName',
          'externalName' => "#{service}.default.svc.cluster.local"
        }
      }
    end
  end
end
