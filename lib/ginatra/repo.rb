require "grit"

module Grit
  class Commit
    # this lets us add a link between commits and refs directly
    attr_accessor :refs

    def ==(other_commit)
      id == other_commit.id
    end
  end
end

module Ginatra

  # A thin wrapper to the Grit::repo class so that we can add a name and a url-sanitised-name
  # to a repo, and also intercept and add refs to the commit objects.
  class Repo

    attr_reader :name, :param, :description

    # Create a new repository, and sort out clever stuff including assigning
    # the param, the name and the description.
    #
    # @todo cleanup!
    #
    # @param [String] path a path to the repository you want created
    # @return [Ginatra::Repo] a repository instance
    def initialize(path)
      @repo = Grit::Repo.new(path)
      @param = File.split(path).last
      @name = @param
      @description = @repo.description
      #@description = "Please edit the #{@repo.path}/description file for this repository and set the description for it." if /^Unnamed repository;/.match(@description)
      @description = '' if /^Unnamed repository;/.match(@description)
    end

    def ==(other_repo)
      # uses method_missing
      path == other_repo.path
    end

    # Return a commit corresponding to the commit to the repo,
    # but with the refs already attached.
    #
    # @see Ginatra::Repo#add_refs
    #
    # @raise [Ginatra::InvalidCommit] if the commit doesn't exist.
    #
    # @param [String] id the commit id
    # @return [Grit::Commit] the commit object.
    def commit(id)
      @commit = @repo.commit(id)
      raise(Ginatra::InvalidCommit.new(id)) if @commit.nil?
      add_refs(@commit,{})
      @commit
    end

    # Return a list of commits to a certain branch, including pagination options and all the refs.
    #
    # @param [String] start the branch to look for commits in
    # @param [Integer] max_count the maximum count of commits
    # @param [Integer] skip the number of commits in the branch to skip before taking the count.
    #
    # @raise [Ginatra::Error] if max_count is less than 0. silly billy!
    #
    # @return [Array<Grit::Commit>] the array of commits.
    def commits(start = 'master', max_count = 10, skip = 0)
      raise(Ginatra::Error.new("max_count cannot be less than 0")) if max_count < 0
      refs_cache = {}
      @repo.commits(start, max_count, skip).each do |commit|
        add_refs(commit,refs_cache)
      end
    end

    # Return a list of commits like --all, including pagination options and all the refs.
    #
    # @param [Integer] max_count the maximum count of commits
    # @param [Integer] skip the number of commits in the branch to skip before taking the count.
    #
    # @raise [Ginatra::Error] if max_count is less than 0. silly billy!
    #
    # @return [Array<GraphCommit>] the array of commits.
    def all_commits(max_count = 10, skip = 0)
      raise(Ginatra::Error.new("max_count cannot be less than 0")) if max_count < 0
      commits = Grit::Commit.find_all(@repo, nil, {:max_count => max_count, :skip => skip})
      ref_cache = {}
      commits.collect do |commit|
        add_refs(commit, ref_cache)
        GraphCommit.new(commit)
      end
    end
    # Adds the refs corresponding to Grit::Commit objects to the respective Commit objects.
    #
    # @todo Perhaps move into commit class.
    #
    # @param [Grit::Commit] commit the commit you want refs added to
    # @param [Hash] empty hash with scope out of loop to speed things up
    # @return [Array] the array of refs added to the commit. they are also on the commit object.
    def add_refs(commit, ref_cache)
      if ref_cache.empty?
         @repo.refs.each {|ref| ref_cache[ref.commit.id] ||= [];ref_cache[ref.commit.id] << ref}
      end
      commit.refs = ref_cache[commit.id] if ref_cache.include? commit.id
      commit.refs ||= []
    end

    # Catch all
    #
    # Warning! contains: Magic
    #
    # @todo update respond_to? method
    def method_missing(sym, *args, &block)
      if @repo.respond_to?(sym)
        @repo.send(sym, *args, &block)
      else
        super
      end
    end

    # to correspond to the #method_missing definition
    def respond_to?(sym)
      @repo.respond_to?(sym) || super
    end

    # not sure why we need this but whatever.
    def to_s
      @name.to_s
    end
  end
end
