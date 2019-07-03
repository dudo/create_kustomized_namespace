# frozen_string_literal: true

require 'yaml'

module Templates
  class Base
    attr_reader :service, :namespace, :options
    
    def initialize(service:, namespace:, **options)
      @service = service
      @namespace = namespace
      @options = options
    end

    def manifest
      {}
    end

    def file_name
      self.class::NAME
    end

    def directory
      [service, 'overlays', namespace]
    end

    def path
      "#{directory.push(file_name).join('/')}.yaml"
    end

    def method_missing(m, *args, &block)
      super unless m.to_s.end_with?('?')

      m.to_s.delete('?') == file_name
    end
  end
end
