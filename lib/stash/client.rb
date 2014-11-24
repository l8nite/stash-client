require "stash/client/version"
require "restclient"
require 'addressable/uri'
require 'json'

module Stash
  class Client

    attr_reader :url

    def initialize(opts = {})
      if opts[:host] && opts[:scheme]
        @url = Addressable::URI.parse(opts[:scheme] + '://' + opts[:host] + '/rest/api/1.0/')
      elsif opts[:host]
        @url = Addressable::URI.parse('http://' + opts[:host] + '/rest/api/1.0/')
      elsif opts[:url]
        @url = Addressable::URI.parse(opts[:url])
      elsif opts[:uri] && opts[:uri].kind_of?(Addressable::URI)
        @url = opts[:uri]
      else
        raise ArgumentError, "must provide :url or :host"
      end

      @url.userinfo = opts[:credentials] if opts[:credentials]
    end

    def projects
      fetch_all 'projects'
    end

    def create_project(opts={})
      post 'projects', opts
    end

    def update_project(project, opts={})
      project_path = project.fetch('link').fetch('url')
      put project_path, opts
    end

    def delete_project(project)
      project_path = project.fetch('link').fetch('url')
      delete project_path
    end

    def repositories
      projects.map do |project|
        repos_path = project.fetch('link').fetch('url') + '/repos'
        fetch_all repos_path
      end.flatten
    end

    def repositories_for(project)
      project_path = project.fetch('link').fetch('url') + '/repos'
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

    def commits_for(repo, opts = {})
      query_values = {}

      path = remove_leading_slash repo.fetch('link').fetch('url').sub('browse', 'commits')
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
      path = remove_leading_slash repo.fetch('link').fetch('url').sub('browse', 'changes')
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

    private

    def fetch_all(uri)
      uri = @url.join(remove_leading_slash(uri)) unless uri.kind_of? Addressable::URI
      response, result = {}, []

      until response['isLastPage']
        response = fetch(uri)
        result += response['values']

        next_page_start = response['nextPageStart'] || (response['start'] + response['size'])
        uri.query_values = (uri.query_values || {}).merge('start' => next_page_start)
      end

      result
    end

    def fetch(uri)
      uri = @url.join(remove_leading_slash(uri)) unless uri.kind_of? Addressable::URI
      JSON.parse(RestClient.get(uri.to_s, :accept => :json))
    end

    def post(uri, data)
      uri = @url.join(remove_leading_slash(uri)) unless uri.kind_of? Addressable::URI
      JSON.parse(
        RestClient.post(
          uri.to_s, data.to_json, :accept => :json, :content_type => :json
        )
      )
    end

    def put(uri, data)
      uri = @url.join(remove_leading_slash(uri)) unless uri.kind_of? Addressable::URI
      JSON.parse(
        RestClient.put(
          uri.to_s, data.to_json, :accept => :json, :content_type => :json
        )
      )
    end

    def delete(uri)
      uri = @url.join(remove_leading_slash(uri)) unless uri.kind_of? Addressable::URI
      RestClient.delete(uri.to_s, :accept => :json)
    end

    def remove_leading_slash(str)
      str.sub(/\A\//, '')
    end

    def repo_path(repository)
      relative_project_path = repository.fetch('project').fetch('link').fetch('url')
      relative_project_path + '/repos/' + repository.fetch('slug')
    end
  end
end
