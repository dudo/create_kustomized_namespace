#!/usr/bin/env ruby
# frozen_string_literal: true

require 'slop'

require_relative 'manifest'

$options = Slop.parse do |o| # rubocop:disable Metrics/BlockLength
  o.banner = 'usage: create_overlay [options]'
  o.separator 'example: create_overlay --service my-service --cluster-repo my-company/my-cluster --target-image my-company/my-service'
  o.separator ''
  o.separator 'options:'
  o.string '-s', '--service',
           'The service to deploy to your cluster',
           default: ENV['SERVICE']
  o.string '-r', '--cluster-repo',
           'GitHub repository that controls your cluster',
           default: ENV['CLUSTER_REPO']
  o.string '-i', '--target-image',
           'Remotely hosted target image',
           default: ENV['TARGET_IMAGE']
  o.string '-n', '--namespace',
           'Desired namespace, or inferred from $GITHUB_HEAD_REF',
           default: ENV['GITHUB_HEAD_REF']&.gsub(/[^\w]/, '-')
  o.string '-t', '--tag',
           'Image tag, or inferred from $GITHUB_SHA',
           default: ENV['GITHUB_SHA']&.[](0..6)
  o.string '-T', '--token',
           'GitHub access token with repos access, _NOT_ $GITHUB_TOKEN',
           default: ENV['TOKEN']
  o.boolean '--flux',
            'Modifies manifests for automated Flux deployments',
            default: false
  o.boolean '--dry-run',
            'Print out yaml files to be created in GitHub - Do NOT commit',
            default: false
  o.boolean '--built',
            'Run Kustomize build during dry-run',
            default: false
end

class String
  def red
    colorize(self, "\e[1m\e[31m")
  end

  private

  def colorize(text, color_code)
    "#{color_code}#{text}\e[0m"
  end
end

def exit_code(message, number, show_options: false)
  puts
  puts message.red
  if show_options
    puts
    puts $options
  end
  puts
  exit number
end

# ensure we have all the appropriate parameters to proceed
puts 'Checking required arguments...'
missing = $options.to_hash.select { |_, v| v.nil? }
missing.delete(:token) if $options[:dry_run]
exit_code("Missing required arguments: #{missing.keys}", 2, show_options: true) if missing.any?

Manifest.create($options.to_hash)
