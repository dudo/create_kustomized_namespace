# frozen_string_literal: true

require_relative 'base'

module Templates
  class Kustomization < Base
    NAME = 'kustomization'

    def manifest
      {
        'kind' => 'Kustomization',
        'namespace' => namespace,
        'bases' => [
          '../../base/'
        ]
      }.tap do |hash|
        hash['resources'] = resources
        hash['patches'] = patches
        hash['patchesJson6902'] = patches_json6902
        hash['images'] = images
      end
    end

    private

    def resources
      [].tap do |array|
        array.push("#{Templates::Namespace::NAME}.yaml") if options[:templates].any?(&:namespace?)
      end
    end

    def patches
      [].tap do |array|
        array.push("#{Templates::Service::NAME}.yaml") if options[:svc]
      end
    end

    def patches_json6902
      [].tap do |array|
        array.push(ingress_patch) if options[:templates].any?(&:ingress?)
      end
    end

    def images
      [].tap do |array|
        array.push(images_patch) if options[:image]
      end
    end

    # https://github.com/kubernetes-sigs/kustomize/blob/master/examples/jsonpatch.md
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

    # https://github.com/kubernetes-sigs/kustomize/blob/master/examples/image.md
    def images_patch
      img_tuple = options[:image].split(':')
      {
        'name' => img_tuple.first,
        'newTag' => img_tuple.last
      }
    end
  end
end
