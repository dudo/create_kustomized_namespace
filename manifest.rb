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

class Manifest
  attr_reader :client, :repo, :service, :namespace, :image, :services

  BASE_DIR = 'base'

  def initialize(service:, cluster_repo:, namespace:, target_image:, tag:, token:)
    puts 'Connecting to GitHub...'
    @client = Octokit::Client.new(access_token: token)
    @repo = cluster_repo
    @service = service
    @namespace = namespace
    @image = "#{target_image}:#{tag}"
    @services = fetch_services
    @templates = []
  end

  def self.create(options = {})
    instance = new(**options.slice(:service, :cluster_repo, :namespace, :target_image, :tag, :token))

    instance.supporting_services.each do |svc|
      instance.create_supporting_manifests(svc)
    end
    instance.create_namespace_manifest
    instance.create_primary_manifests
    instance.create_flux_manifest if options[:flux]

    if options[:dry_run]
      instance.dry_run(options[:built])
    else
      instance.commit_overlay_to_github
      puts 'Done!'
    end
  end

  def supporting_services
    services - [service]
  end

  def create_namespace_manifest
    return puts "Using existing namespace '#{namespace}'" unless include_namespace?

    puts "Creating namespace '#{namespace}'..."
    @templates << Templates::Namespace.new(service: service, namespace: namespace)
  end

  def create_primary_manifests # rubocop:disable Metrics/AbcSize
    puts "Creating #{service} manifests with #{image}..."
    # check each type of file for the service we're updating, and create an overlay

    @templates << Templates::Ingress.new(service: service, namespace: namespace, hosts: base_ingress_hosts(service)) if include_ingress?(service)
    @templates << Templates::Kustomization.new(service: service, namespace: namespace, image: image, templates: @templates)
  end

  def create_flux_manifest
    generators = flux_generators
    services.each do |svc|
      generators << { 'command' => "kustomize build ./#{svc}/overlays/#{namespace}" }
    end

    @templates << Templates::Flux.new(service: service, namespace: namespace, generators: generators.uniq)
  end

  def create_supporting_manifests(svc) # rubocop:disable Metrics/AbcSize
    return puts "Using existing manifests for #{svc}" unless create_overlay?(svc)

    puts "Creating #{svc} manifests pointing to #{svc}.default.svc.cluster.local..."

    @templates << Templates::Ingress.new(service: svc, namespace: namespace, hosts: base_ingress_hosts(svc)) if include_ingress?(svc)
    @templates << Templates::Service.new(service: svc, namespace: namespace) if include_service?(svc)
    @templates << Templates::Kustomization.new(service: svc, namespace: namespace, templates: @templates, primary: false)
  end

  def commit_overlay_to_github # rubocop:disable Metrics/AbcSize
    puts "Creating overlays for '#{namespace}' in GitHub repository #{repo}..."
    ref = 'heads/master'
    sha_latest_commit = client.ref(repo, ref).object.sha

    sha_base_tree = client.commit(repo, sha_latest_commit).commit.tree.sha

    sha_new_tree = client.create_tree(repo, new_blobs, base_tree: sha_base_tree).sha

    commit_message = "Create #{service} in namespace '#{namespace}' with image #{image}"
    sha_new_commit = client.create_commit(repo, commit_message, sha_new_tree, sha_latest_commit).sha
    client.update_ref(repo, ref, sha_new_commit)
  end

  def dry_run(built = false)
    puts @templates.any? ? 'Printing yaml files...' : 'No yaml files to print!'
    puts
    built ? print_manifests : print_templates
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
    hash = YAML.safe_load Base64.decode64(flux.content)
    hash['commandUpdated']['generators']
  rescue StandardError
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
    !manifests.include?(Templates::Namespace::NAME)
  end

  def base_manifests(svc)
    @base_manifests ||= {}
    @base_manifests[svc] ||= client.contents(repo, path: [svc, BASE_DIR].join('/')).select { |c| c[:type] == 'file' }
  end

  def base_manifest_names(svc)
    base_manifests(svc).map { |m| m.name.gsub(/.ya*ml/, '') }
  rescue StandardError
    []
  end

  def overlay_manifests(svc)
    @overlay_manifests ||= {}
    @overlay_manifests[svc] ||= client.contents(repo, path: [svc, 'overlays', namespace].join('/')).select { |c| c[:type] == 'file' }
  end

  def overlay_manifest_names(svc)
    overlay_manifests(svc).map { |m| m.name.gsub(/.ya*ml/, '') }
  rescue StandardError
    []
  end

  def base_ingress_hosts(svc)
    ingress = client.contents(repo, path: [svc, BASE_DIR, "#{Templates::Ingress::NAME}.yaml"].join('/'))
    hash = YAML.safe_load Base64.decode64(ingress.content)
    hash['spec']['rules'].map { |r| r['host'] }
  rescue StandardError
    []
  end

  def new_blobs
    @templates.map do |t|
      {
        path: t.path,
        mode: '100644',
        type: 'blob',
        sha: client.create_blob(repo, Base64.encode64(t.manifest.to_yaml), 'base64')
      }
    end
  end

  def print_templates
    @templates.each do |t|
      puts t.manifest.to_yaml
    end
    puts "\n"
  end

  def print_manifests # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    services.each do |svc|
      base_manifests(svc).each do |m|
        FileUtils.mkdir_p "/tmp/#{svc}/base"
        File.write "/tmp/#{m.path}", Base64.decode64(client.contents(repo, path: m.path).content)
      end
    end

    @templates.each do |t|
      FileUtils.mkdir_p "/tmp/#{t.directory.join('/')}"
      File.write "/tmp/#{t.path}", t.manifest.to_yaml
    end

    puts @templates.find(&:flux?)&.manifest&.to_yaml
    @templates.map(&:directory).uniq.each do |dir|
      next if dir.empty?

      puts '---'
      puts `kustomize build /tmp/#{dir.join('/')}`
    end

    puts "\n"
  end
end
