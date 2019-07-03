# frozen_string_literal: true

require_relative 'base'

module Templates
  class Kustomization < Base
    NAME = 'kustomization'

    def initialize(service:, namespace:, **options)
      super
      @resources = [].tap do |array|
        array.push("#{Templates::Namespace::NAME}.yaml") if $templates.any? { |t| t.namespace? }
      end
      @patches = [].tap do |array|
        array.push("#{Templates::Service::NAME}.yaml") if options[:svc]
      end
      @patches_json_6902 = [].tap do |array|
        array.push(ingress_patch) if $templates.any? { |t| t.ingress? }
      end
      @images = [].tap do |array|
        array.push(images_patch) if options[:img]
      end
    end
    
    def manifest
      {
        'kind' => 'Kustomization',
        'apiVersion' => 'kustomize.config.k8s.io/v1beta1',
        'namespace' => namespace,
        'bases' => [
          '../../base/'
        ]
      }.tap do |hash|
        hash['resources'] = @resources
        hash['patches'] = @patches
        hash['patchesJson6902'] = @patches_json_6902
        hash['images'] = @images
      end
    end

    private

    def ingress_patch
      {
        'target' => { 
          'kind' => 'Ingress', 
          'group' => 'extensions', 
          'version' => 'v1beta1', 
          'name' => service 
        },
        'path' => 'ingress.yaml'
      }
    end

    def images_patch
      { 
        'name' => $opts[:target_image],
        'newTag' => $opts[:tag]
      }
    end
  end
end
