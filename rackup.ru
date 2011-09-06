$LOAD_PATH.push('lib')
require "ginatra"
require 'bundler'

Bundler.require

map '/' do
  run Ginatra::App
end
