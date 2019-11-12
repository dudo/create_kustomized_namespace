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

    def method_missing(method_name, *args, &block)
      super unless method_name.to_s.end_with?('?')

      method_name.to_s.delete('?') == file_name.delete('.')
    end

    def respond_to_missing?(method_name, include_private = false)
      method_name.to_s.end_with?('?') || super
    end
  end
end
