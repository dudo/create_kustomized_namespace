# frozen_string_literal: true

require 'octokit'
require 'fileutils'

require_relative 'templates/kustomization'
require_relative 'templates/flux'
require_relative 'templates/ingress'
require_relative 'templates/namespace'
require_relative 'templates/service'

Octokit.configure do |c|
  c.connection_options = {
    request: {
      open_timeout: 5,
      timeout: 5
    }
  }
end

class String
  def red; colorize(self, "\e[1m\e[31m"); end
  def green; colorize(self, "\e[1m\e[32m"); end
  def colorize(text, color_code)  "#{color_code}#{text}\e[0m" end
end

class Manifest
  attr_reader :client, :repo, :service, :namespace, :services

  def initialize
    puts 'Connecting to GitHub...'
    @client = Octokit::Client.new(access_token: $opts[:token])
    @repo = $opts[:cluster_repo]
    @service = $opts[:service]
    @namespace = $opts[:namespace]
    @services = fetch_services
    $templates = []
  end

  def self.create
    instance = self.new
    
    instance.supporting_services.each do |svc|
      instance.create_supporting_manifests(svc)
    end
    instance.create_namespace_manifest
    instance.create_primary_manifests
    instance.create_flux_manifest if $opts[:flux]

    return instance.dry_run if $opts[:dry_run]
    
    instance.commit_overlay_to_github
    puts 'Done!'
  end

  def supporting_services
    services - [service]
  end

  def create_namespace_manifest
    return puts "Using existing namespace '#{namespace}'" unless include_namespace?
    
    puts "Creating namespace '#{namespace}'..."
    $templates << Templates::Namespace.new(service: service, namespace: namespace)
  end

  def create_primary_manifests
    puts "Creating #{service} manifests with #{$opts[:target_image]}:#{$opts[:tag]}..."
    # check each type of file for the service we're updating, and create an overlay
    
    $templates << Templates::Ingress.new(service: service, namespace: namespace, hosts: base_ingress_hosts(service)) if include_ingress?(service)
    $templates << Templates::Kustomization.new(service: service, namespace: namespace, img: true)
  end

  def create_flux_manifest
    generators = flux_generators
    services.each do |svc|
      generators << { 'command' => "kustomize build ./#{svc}/overlays/#{namespace}" }
    end
    generators.uniq
    $templates << Templates::Flux.new(service: service, namespace: namespace, generators: generators)
  end

  def create_supporting_manifests(svc)   
    return puts "Using existing manifests for #{svc}" unless create_overlay?(svc)

    puts "Creating #{svc} manifests pointing to #{svc}.default.svc.cluster.local..."
    
    $templates << Templates::Ingress.new(service: svc, namespace: namespace, hosts: base_ingress_hosts(svc)) if include_ingress?(svc)
    $templates << Templates::Service.new(service: svc, namespace: namespace) if include_service?(svc)
    $templates << Templates::Kustomization.new(service: svc, namespace: namespace, svc: true)
  end

  def commit_overlay_to_github
    puts "Creating overlays for '#{namespace}' in GitHub repository #{repo}..."
    ref = 'heads/master'
    sha_latest_commit = client.ref(repo, ref).object.sha
    
    sha_base_tree = client.commit(repo, sha_latest_commit).commit.tree.sha
    
    sha_new_tree = client.create_tree(repo, new_blobs, { base_tree: sha_base_tree }).sha
    
    commit_message = "Create #{service} in namespace '#{namespace}' with image #{$opts[:target_image]}:#{$opts[:tag]}"
    sha_new_commit = client.create_commit(repo, commit_message, sha_new_tree, sha_latest_commit).sha
    updated_ref = client.update_ref(repo, ref, sha_new_commit)
  end

  def dry_run
    puts $templates.any? ? 'Printing yaml files...' : 'No yaml files to print!'
    puts
    $opts[:built] ? print_manifests : print_templates
  end

  private

  def fetch_services
    puts 'Collecting known services...'
    services = client.contents(repo).select { |c| c[:type] == 'dir' }.map(&:name)
    if services.include? service
      puts "Found services #{services}"
      services
    else
      exit_code("Unknown service. Please choose one of #{services}", 2) 
    end
  end

  def flux_generators
    flux = client.contents(repo, path: "#{Templates::Flux::NAME}.yaml")
    hash = YAML.load Base64.decode64(flux.content)
    hash['commandUpdated']['generators']
  rescue
    []
  end

  def include_ingress?(svc)
    base_manifest_names(svc).include?(Templates::Service::NAME)
  end

  def include_service?(svc)
    base_manifest_names(svc).include?(Templates::Service::NAME)
  end

  def create_overlay?(svc)
    overlay_manifest_names(svc).empty?
  end

  def include_namespace?
    manifests = supporting_services.map { |svc| overlay_manifest_names(svc) }.flatten
    manifests.include?(Templates::Namespace::NAME)
  end

  def base_manifests(svc)
    @base_manifests ||= {}
    @base_manifests[svc] ||= client.contents(repo, path: [svc, 'base'].join('/')).select { |c| c[:type] == 'file' }
  end

  def base_manifest_names(svc)
    base_manifests(svc).map { |m| m.name.gsub /.ya*ml/, '' }
  rescue
    []
  end

  def overlay_manifests(svc)
    @overlay_manifests ||= {}
    @overlay_manifests[svc] ||= client.contents(repo, path: [svc, 'overlays', namespace].join('/')).select { |c| c[:type] == 'file' }
  end

  def overlay_manifest_names(svc)
    overlay_manifests(svc).map { |m| m.name.gsub /.ya*ml/, '' }
  rescue
    []
  end

  def base_ingress_hosts(svc)
    ingress = client.contents(repo, path: [svc, 'base', "#{Templates::Ingress::NAME}.yaml"].join('/'))
    hash = YAML.load Base64.decode64(ingress.content)
    hash['spec']['rules'].map { |r| r['host'] }
  rescue
    []
  end

  def new_blobs
    $templates.map do |t|
      { 
        path: t.path, 
        mode: '100644', 
        type: 'blob', 
        sha: client.create_blob(repo, Base64.encode64(t.manifest.to_yaml), 'base64') 
      }
    end
  end

  def print_templates
    $templates.each do |t|
      puts t.manifest.to_yaml
    end
    puts "\n"
  end

  def print_manifests
    services.each do |svc| 
      base_manifests(svc).each do |m|
        FileUtils.mkdir_p "/tmp/#{svc}/base"
        File.write "/tmp/#{m.path}", Base64.decode64(client.contents(repo, path: m.path).content)
      end
    end

    $templates.each do |t|
      FileUtils.mkdir_p "/tmp/#{t.directory.join('/')}"
      File.write "/tmp/#{t.path}", t.manifest.to_yaml
    end

    $templates.map(&:directory).uniq.each do |dir|
      puts '---'
      puts `kustomize build /tmp/#{dir.join('/')}`
    end
    puts "\n"
  end
end
