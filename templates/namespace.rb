# frozen_string_literal: true

require_relative 'base'

module Templates
  class Namespace < Base
    NAME = 'namespace'

    def manifest
      {
        'kind' => 'Namespace',
        'apiVersion' => 'v1',
        'metadata' => {
          'name' => namespace
        }
      }
    end
  end
end
