#!/usr/bin/env ruby
# Runs the gallery manager on the loopback interface and opens it.
#
#   mise run galleries          # the usual way in
#   PORT=4321 mise run galleries
#   NO_OPEN=1 mise run galleries # do not launch a browser

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "securerandom"
require "socket"

require "rack/handler/puma"
require "server"

REPO_ROOT = File.expand_path("../..", __dir__)
DEFAULT_PORT = 4001

def die(message)
  warn "error: #{message}"
  exit 1
end

def free_port(preferred)
  (preferred..preferred + 20).find { |port| port_free?(port) } ||
    die("no free port between #{preferred} and #{preferred + 20}")
end

def port_free?(port)
  TCPServer.new("127.0.0.1", port).close
  true
rescue Errno::EADDRINUSE
  false
end

repo = GalleryManager::Repo.new(REPO_ROOT)
die("#{repo.galleries_path} is missing; run this from the site repo") unless repo.galleries_path.exist?

store = GalleryManager::Store.new(repo: repo, scripts: GalleryManager::Scripts.new(repo))
token = SecureRandom.hex(16)
port = free_port(Integer(ENV.fetch("PORT", DEFAULT_PORT)))
url = "http://127.0.0.1:#{port}/"

puts "Galleries: #{url}"
puts "Editing #{repo.root}. Changes are written straight to the working tree; git is the undo."
Thread.new { sleep 0.5; system("open", url) } unless ENV["NO_OPEN"]

Rack::Handler::Puma.run(
  GalleryManager::App.serving(store: store, token: token),
  Host: "127.0.0.1", Port: port, Silent: true
)
