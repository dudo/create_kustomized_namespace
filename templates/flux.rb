# frozen_string_literal: true

# https://docs.fluxcd.io/en/latest/references/fluxyaml-config-files.html

require_relative 'base'

module Templates
  class Flux < Base
    NAME = '.flux'

    def manifest
      {
        'version' => 1,
        'commandUpdated' => {
          'generators' => generators
        }
      }
    end

    def directory
      []
    end

    def generators
      options[:generators] || []
    end
  end
end
