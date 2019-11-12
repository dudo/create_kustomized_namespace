# frozen_string_literal: true

require_relative 'base'

module Templates
  class Flux < Base
    NAME = '.flux'

    def manifest
      {
        'version' => 1,
        'commandUpdated' => {
          'generators' => options[:generators] || []
        }
      }
    end

    def directory
      []
    end
  end
end
