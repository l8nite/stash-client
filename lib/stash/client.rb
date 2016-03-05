require "stash/client/version"
require "restclient"
require 'addressable/uri'
require 'json'

module Stash
  class Client

    REST_API = '/rest/api/1.0/'
    BRANCH_UTIL_API = '/rest/branch-utils/1.0/'

    attr_reader :url
    attr_reader :credentials

    def initialize(opts = {})
      if opts[:host] && opts[:scheme]
        base = Addressable::URI.parse(opts[:scheme] + '://' + opts[:host])
        @url = base.join(REST_API)
        @burl = base.join(BRANCH_UTIL_API)
      elsif opts[:host]
        base = Addressable::URI.parse('http://' + opts[:host])
        @url = base.join(REST_API)
        @burl = base.join(BRANCH_UTIL_API)
      elsif opts[:url]
        base = Addressable::URI.parse(opts[:url])
        @url = base.join(REST_API)
        @burl = base.join(BRANCH_UTIL_API)
      elsif opts[:uri] && opts[:uri].kind_of?(Addressable::URI)
        base = opts[:uri]
        @url = base
        if base.path eq REST_API
          @burl = Addressable::URI.parse(base.site + remove_leading_slash(BRANCH_UTIL_API))
        end
      else
        raise ArgumentError, "must provide :url or :host"
      end

      @credentials = opts[:credentials] if opts[:credentials]

      @url.userinfo = @credentials
      @burl.userinfo = @credentials
    end

    def projects
      fetch_all 'projects'
    end

    def create_project(opts={})
      post 'projects', opts
    end

    def update_project(project, opts={})
      project_path = project.fetch('links').fetch('self').first['href']
      put project_path, opts
    end

    def delete_project(project)
      project_path = project.fetch('links').fetch('self').first['href']
      delete project_path
    end

    def repositories
      projects.map do |project|
        repos_path = project.fetch('links').fetch('self').first['href'] + '/repos'
        fetch_all repos_path
      end.flatten
    end

    def repositories_for(project)
      project_path = project.fetch('links').fetch('self').first['href'] + '/repos'
      repos = fetch_all project_path
      repos.flatten
    end

    def update_repository(repository, opts={})
      put repo_path(repository), opts
    end

    def project_keyed(key)
      projects.find { |e| e['key'] == key }
    end

    def project_named(name)
      projects.find { |e| e['name'] == name }
    end

    def repository_named(name, project = nil)
      if project.nil?
        repositories.find { |e| e['name'] == name }
      else
        repositories_for(project).find { |e| e['name'] == name }
      end
    end

    def default_branch_for(repository)
      default_branch_path = repo_path(repository) + '/branches/default'
      fetch default_branch_path
    end

    def set_default_branch_for(repository, branch_id)
      default_branch_path = repo_path(repository) + '/branches/default'
      put default_branch_path, { id: branch_id}
    end

    def branches_matching(repository, filter = nil)
      default_branch_path = repo_path(repository) + '/branches'
      args = filter.nil? ? {} : { filterText: filter }
      fetch_all default_branch_path, args
    end

    def create_branch(repository, branch_name, start_point)
      branch_path = repo_path(repository) + '/branches'
      url = @burl.join(remove_leading_slash branch_path)
      post url, {
        name: branch_name,
        startPoint: start_point
      }
    end

    def files_for(repository)
      files_path = repo_path(repository) + '/files'
      fetch_all files_path
    end

    def hooks_for(repository)
      hooks_path = repo_path(repository) + '/settings/hooks'
      fetch_all hooks_path
    end

    def hook_settings(repository, key)
      hook_settings_path = repo_path(repository) + '/settings/hooks/' + key + '/settings'
      fetch hook_settings_path
    end

    def hook_enable(repository, key, settings = {})
      hook_enabled_path = repo_path(repository) + '/settings/hooks/' + key + '/enabled'
      put hook_enabled_path, settings
    end

    def hook_disable(repository, key)
      hook_enabled_path = repo_path(repository) + '/settings/hooks/' + key + '/enabled'
      delete hook_enabled_path
    end

    def commits_for(repo, opts = {})
      query_values = {}

      path = remove_leading_slash repo.fetch('links').fetch('self').first['href'].sub('browse', 'commits')
      uri = @url.join(path)

      query_values['since'] = opts[:since] if opts[:since]
      query_values['until'] = opts[:until] if opts[:until]
      query_values['limit'] = Integer(opts[:limit]) if opts[:limit]

      if query_values.empty?
        # default limit to 100 commits
        query_values['limit'] = 100
      end

      uri.query_values = query_values

      if query_values['limit'] && query_values['limit'] < 100
        fetch(uri).fetch('values')
      else
        fetch_all(uri)
      end
    end

    def changes_for(repo, sha, opts = {})
      path = remove_leading_slash repo.fetch('links').fetch('self').first['href'].sub('browse', 'changes')
      uri = @url.join(path)

      query_values = { 'until' =>  sha }
      query_values['since'] = opts[:parent] if opts[:parent]
      query_values['limit'] = opts[:limit] if opts[:limit]

      uri.query_values = query_values

      if query_values['limit']
        fetch(uri).fetch('values')
      else
        fetch_all(uri)
      end
    end

    def create_repo(project, opts={})
      post "projects/#{project}/repos", opts
    end

    private

    def fetch_all(uri, args = {})
      uri = @url.join(remove_leading_slash(uri)) unless uri.kind_of? Addressable::URI
      uri.query_values = (uri.query_values || {}).merge(args)
      response, result = {}, []

      until response['isLastPage']
        response = fetch(uri)
        result += response['values']

        next_page_start = response['nextPageStart'] || (response['start'] + response['size'])
        uri.query_values = (uri.query_values || {}).merge('start' => next_page_start)
      end

      result
    end

    def fetch(uri, args = {})
      uri = @url.join(remove_leading_slash(uri)) unless uri.kind_of? Addressable::URI
      uri.query_values = (uri.query_values || {}).merge(args)

      response = RestClient.get(uri.to_s, :accept => :json)

      response.present? ? JSON.parse(response) : nil
    end

    def post(uri, data)
      uri = @url.join(remove_leading_slash(uri)) unless uri.kind_of? Addressable::URI

      response = RestClient.post(
        uri.to_s, data.to_json, :accept => :json, :content_type => :json
      )

      response.present? ? JSON.parse(response) : nil
    end

    def put(uri, data)
      uri = @url.join(remove_leading_slash(uri)) unless uri.kind_of? Addressable::URI

      response = RestClient.put(
        uri.to_s, data.to_json, :accept => :json, :content_type => :json
      )

      response.present? ? JSON.parse(response) : nil
    end

    def delete(uri)
      uri = @url.join(remove_leading_slash(uri)) unless uri.kind_of? Addressable::URI
      RestClient.delete(uri.to_s, :accept => :json)
    end

    def remove_leading_slash(str)
      str.sub(/\A\//, '')
    end

    def repo_path(repository)
      relative_project_path = repository.fetch('project').fetch('links').fetch('self').first['href']
      relative_project_path + '/repos/' + repository.fetch('slug')
    end
  end
end
