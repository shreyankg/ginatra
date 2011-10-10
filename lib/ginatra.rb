
require 'sinatra/base'
require "sinatra/partials"
require 'json'

# Written myself. i know, what the hell?!
module Ginatra

  autoload :Config,   "ginatra/config"
  autoload :Helpers,  "ginatra/helpers"
  autoload :Repo,     "ginatra/repo"
  autoload :RepoList, "ginatra/repo_list"
  autoload :GraphCommit, "ginatra/graph_commit"

  # A standard error class for inheritance.
  class Error < StandardError; end

  # An error related to a commit somewhere.
  class CommitsError < Error
    def initialize(repo)
      super("Something went wrong looking for the commits for #{repo}")
    end
  end

  # Error raised when commit ref passed in parameters
  # does not exist in repository
  class InvalidCommit < Error
    def initialize(id)
      super("Could not find a commit with the id of #{id}")
    end
  end

  VERSION = "3.0.1"

  # The main application class.
  #
  # This class contains all the core application logic
  # and is what is mounted by the +rackup.ru+ files.
  class App < Sinatra::Base

    # logger that can be used with the Sinatra code
    def logger
      Ginatra::Config.logger
    end

    configure do
      Config.load!
      set :host, Ginatra::Config[:host]
      set :port, Ginatra::Config[:port]
      set :raise_errors, Proc.new { test? }
      set :show_exceptions, Proc.new { development? }
      set :dump_errors, true
      set :logging, Proc.new { !test? }
      set :static, true
      current_path = File.expand_path(File.dirname(__FILE__))
      set :public, "#{current_path}/../public"
      set :views, "#{current_path}/../views"
      set :haml, {:format => :html5}
      set :scss, {:style => :compact, :debug_info => false}
    end

    helpers Helpers, Sinatra::Partials

    # Let's handle a CommitsError.
    #
    # @todo prettify
    error CommitsError do
      'No commits were returned for ' + request.uri
    end

    # The root route
    # This works by interacting with the Ginatra::Repolist singleton.
    get '/' do
      haml :index
    end

    # CSS
    get '/:name.css' do
      content_type 'text/css', :charset => 'utf-8'
      scss :"../public/src/#{params[:name]}"
    end

    # The project route
    # Shows source code tree and recent commit
    #
    # @param [String] repo the repository url-sanitised-name
    get '/:repo/?' do
      @repo = RepoList.find(params[:repo])
      @commit = @repo.commit('master')

      if (tag = @repo.git.rev_parse({'--verify' => ''}, "#{params[:tree]}^{tree}")).empty?
        # we don't have a tree.
        not_found
      else
        etag(tag) if Ginatra::App.production?
      end

      @tree = @repo.commits.first.tree
      @path = {}
      @path[:tree] = "#{params[:repo]}/tree/#{@tree.id}"
      @path[:blob] = "#{params[:repo]}/blob/#{@tree.id}"
      haml :tree
    end

    # The atom feed of recent commits to a +repo+.
    #
    # This only returns commits to the +master+ branch.
    #
    # @param [String] repo the repository url-sanitised-name
    get '/:repo.atom' do
      @repo = RepoList.find(params[:repo])
      @commits = @repo.commits
      return "" if @commits.empty?
      etag(@commits.first.id) if Ginatra::App.production?
      builder :atom, :layout => nil
    end

    # The html page for a +repo+.
    #
    # Shows the most recent commits in a log format
    #
    # @param [String] repo the repository url-sanitised-name
    get '/:repo/commits' do
      @repo = RepoList.find(params[:repo])
      @commits = @repo.commits
      etag(@commits.first.id) if Ginatra::App.production?
      haml :log
    end

    get '/:repo/graph' do
      @repo = RepoList.find(params[:repo])
      max_count = 650
      max_count = params[:max_count].to_i unless params[:max_count].nil?
      commits = @repo.all_commits(max_count)

      days = GraphCommit.index_commits(commits)
      @days_json = days.compact.collect{|d|[d.day,d.strftime("%b")]}.to_json
      @commits_json = commits.collect do |c|
        h = {}
        h[:parents] = c.parents.collect do |p|
          [p.id,0,0]
        end
        h[:author] = c.author.name.force_encoding("UTF-8")
        h[:time] = c.time
        h[:space] = c.space
        h[:refs] = c.refs.collect{|r|r.name}.join(" ") unless c.refs.nil?
        h[:id] = c.sha
        h[:date] = c.date
        h[:message] = c.message.force_encoding("UTF-8")
        h[:login] = c.author.email
        h
      end.to_json
      haml :graph
    end

    # The atom feed of recent commits to a certain branch of a +repo+.
    #
    # @param [String] repo the repository url-sanitised-name
    # @param [String] ref the repository ref
    get '/:repo/:ref.atom' do
      @repo = RepoList.find(params[:repo])
      @commits = @repo.commits(params[:ref])
      return "" if @commits.empty?
      etag(@commits.first.id) if Ginatra::App.production?
      builder :atom, :layout => nil
    end

    # The patch file for a given commit to a +repo+.
    #
    # @param [String] repo the repository url-sanitised-name
    # @param [String] commit the repository commit
    get '/:repo/commit/:commit.patch' do
      response['Content-Type'] = "text/plain"
      @repo = RepoList.find(params[:repo])
      @repo.git.format_patch({}, "--stdout", "-1", params[:commit])
    end

    # The html representation of a commit.
    #
    # @param [String] repo the repository url-sanitised-name
    # @param [String] commit the repository commit
    get '/:repo/commit/:commit' do
      @repo = RepoList.find(params[:repo])
      @commit = @repo.commit(params[:commit]) # can also be a ref
      etag(@commit.id) if Ginatra::App.production?
      haml(:commit)
    end

    # Download an archive of a given tree!
    #
    # @param [String] repo the repository url-sanitised-name
    # @param [String] tree the repository tree
    get '/:repo/archive/:tree.tar.gz' do
      response['Content-Type'] = "application/x-tar-gz"
      @repo = RepoList.find(params[:repo])
      @repo.archive_tar_gz(params[:tree])
    end

    # HTML page for a given tree in a given +repo+
    #
    # @todo cleanup!
    # @param [String] repo the repository url-sanitised-name
    # @param [String] tree the repository tree
    get '/:repo/tree/:tree' do
      @repo = RepoList.find(params[:repo])

      if (tag = @repo.git.rev_parse({'--verify' => ''}, "#{params[:tree]}^{tree}")).empty?
        # we don't have a tree.
        not_found
      else
        etag(tag) if Ginatra::App.production?
      end

      @tree = @repo.tree(params[:tree]) # can also be a ref (i think)
      @path = {}
      @path[:tree] = "#{params[:repo]}/tree/#{params[:tree]}"
      @path[:blob] = "#{params[:repo]}/blob/#{params[:tree]}"
      haml(:tree)
    end

    # HTML page for a given tree in a given +repo+.
    #
    # This one supports a splat parameter so you can specify a path
    #
    # @todo cleanup!
    # @param [String] repo the repository url-sanitised-name
    # @param [String] tree the repository tree
    get '/:repo/tree/:tree/*' do # for when we specify a path
      @repo = RepoList.find(params[:repo])
      @tree = @repo.tree(params[:tree])/params[:splat].first # can also be a ref (i think)
      if @tree.is_a?(Grit::Blob)
        # we need @tree to be a tree. if it's a blob, send it to the blob page
        # this allows people to put in the remaining part of the path to the file, rather than endless clicks like you need in github
        redirect "#{params[:repo]}/blob/#{params[:tree]}/#{params[:splat].first}"
      else
        etag(@tree.id) if Ginatra::App.production?
        @path = {}
        @path[:tree] = "#{params[:repo]}/tree/#{params[:tree]}/#{params[:splat].first}"
        @path[:blob] = "#{params[:repo]}/blob/#{params[:tree]}/#{params[:splat].first}"
        haml(:tree)
      end
    end

    # HTML page for a given blob in a given +repo+
    #
    # @param [String] repo the repository url-sanitised-name
    # @param [String] tree the repository tree
    get '/:repo/blob/:blob' do
      @repo = RepoList.find(params[:repo])
      @blob = @repo.blob(params[:blob])
      etag(@blob.id) if Ginatra::App.production?
      haml(:blob)
    end

    # HTML page for a given blob in a given repo.
    #
    # Uses a splat param to specify a blob path.
    #
    # @todo cleanup!
    # @param [String] repo the repository url-sanitised-name
    # @param [String] tree the repository tree
    get '/:repo/blob/:tree/*' do
      @repo = RepoList.find(params[:repo])
      @blob = @repo.tree(params[:tree])/params[:splat].first
      if @blob.is_a?(Grit::Tree)
        # as above, we need @blob to be a blob. if it's a tree, send it to the tree page
        # this allows people to put in the remaining part of the path to the folder, rather than endless clicks like you need in github
        redirect "/#{params[:repo]}/tree/#{params[:tree]}/#{params[:splat].first}"
      else
        etag(@blob.id) if Ginatra::App.production?
        haml(:blob)
      end
    end

    # The html page for a given +ref+ of a +repo+.
    #
    # Shows the most recent commits in a log format
    #
    # @param [String] repo the repository url-sanitised-name
    # @param [String] ref the repository ref
    get '/:repo/:ref' do
      params[:page] = 1
      @repo = RepoList.find(params[:repo])
      @commits = @repo.commits(params[:ref])
      etag(@commits.first.id) if Ginatra::App.production?
      haml :log
    end

    # pagination route for the commits to a given ref in a +repo+.
    #
    # @todo cleanup!
    # @param [String] repo the repository url-sanitised-name
    # @param [String] ref the repository ref
    get '/:repo/:ref/:page' do
      pass unless params[:page] =~ /^(\d)+$/
      params[:page] = params[:page].to_i
      @repo = RepoList.find(params[:repo])
      @commits = @repo.commits(params[:ref], 10, (params[:page] - 1) * 10)
      @next_commits = !@repo.commits(params[:ref], 10, params[:page] * 10).empty?
      if params[:page] - 1 > 0
        @previous_commits = !@repo.commits(params[:ref], 10, (params[:page] - 1) * 10).empty?
      end
      @separator = @next_commits && @previous_commits
      haml :log
    end

  end # App

end # Ginatra
