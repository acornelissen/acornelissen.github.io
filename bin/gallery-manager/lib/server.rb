require "json"
require "openssl"
require "securerandom"
require "tmpdir"
require "fileutils"
require "uri"

require "sinatra/base"

require "gallery_data"
require "repo"
require "scripts"
require "store"
require "health"

module GalleryManager
  # The HTTP face of the manager. Holds no logic of its own beyond guarding
  # what comes in: every request is checked before it reaches the store, and
  # every response carries the state read back from disk afterwards.
  class App < Sinatra::Base
    TOOL_ROOT = File.expand_path("..", __dir__).freeze
    # Only the photography tree is ever served.
    SERVABLE = %r{\Aassets/(?:ph|thumbs/ph)/}.freeze
    MAX_UPLOADS = 50

    set :root, TOOL_ROOT
    set :public_folder, File.join(TOOL_ROOT, "public")
    set :views, File.join(TOOL_ROOT, "views")
    set :show_exceptions, false
    set :raise_errors, false
    set :logging, true
    # The tool binds to the loopback interface; its own token and origin checks
    # do the guarding from there.
    set :host_authorization, permitted_hosts: []

    # Not `build`: Sinatra uses that name for assembling its middleware.
    def self.serving(store:, token: SecureRandom.hex(16))
      app = Class.new(self)
      app.set :store, store
      app.set :health, Health.new(repo: store.repo, store: store)
      app.set :token, token
      app
    end

    # --- guards ------------------------------------------------------------

    before do
      next unless request.path_info.start_with?("/api/")
      next if request.get?

      halt 403, json_error("this session's token is missing or wrong") unless token_ok?
      halt 403, json_error("that request came from somewhere else") unless origin_ok?
    end

    # --- reading -----------------------------------------------------------

    get "/" do
      content_type :html
      File.read(File.join(settings.views, "index.html"))
          .sub("__TOKEN__", settings.token)
    end

    get "/api/state" do
      json_response
    end

    get "/assets/*" do
      serve_asset(params["splat"].first.to_s)
    end

    # --- photos ------------------------------------------------------------

    post "/api/photos/reorder" do
      body = read_json
      store.reorder_photos(field(body, "gallery"), array_field(body, "names"))
      json_response
    end

    post "/api/photos/caption" do
      body = read_json
      store.set_caption(field(body, "gallery"), field(body, "photo"), field(body, "caption", allow_empty: true))
      json_response
    end

    post "/api/photos/cover" do
      body = read_json
      store.set_cover(field(body, "gallery"), field(body, "photo"))
      json_response
    end

    post "/api/photos/delete" do
      body = read_json
      store.delete_photo(field(body, "gallery"), field(body, "photo"))
      json_response
    end

    post "/api/photos/move" do
      body = read_json
      store.move_photo(field(body, "from"), field(body, "to"), field(body, "photo"))
      json_response
    end

    # Multipart, because this is where files arrive from Finder.
    post "/api/photos/add" do
      uploads = Array(params["files"]).compact
      raise InvalidRequest, "no files arrived" if uploads.empty?
      raise InvalidRequest, "too many files at once" if uploads.length > MAX_UPLOADS

      stage(uploads) { |paths| store.add_photos(field(params, "gallery"), paths) }
      json_response
    end

    # --- galleries ---------------------------------------------------------

    post "/api/galleries/create" do
      body = read_json
      store.create_gallery(id: field(body, "id"), title: field(body, "title"),
                           section: field(body, "section"), slug: field(body, "slug"))
      json_response
    end

    post "/api/galleries/update" do
      body = read_json
      store.update_gallery(field(body, "gallery"), title: body["title"], section: body["section"])
      json_response
    end

    post "/api/galleries/delete" do
      store.delete_gallery(field(read_json, "gallery"))
      json_response
    end

    post "/api/galleries/reorder" do
      store.reorder_galleries(array_field(read_json, "ids"))
      json_response
    end

    post "/api/repair" do
      settings.health.repair
      json_response
    end

    # --- failures ----------------------------------------------------------

    not_found do
      content_type :json
      json_error("not found")
    end

    error InvalidRequest do
      status 422
      content_type :json
      json_error(env["sinatra.error"].message)
    end

    error Error do
      status 500
      content_type :json
      json_error(env["sinatra.error"].message)
    end

    error JSON::ParserError do
      status 400
      content_type :json
      json_error("that request was not readable JSON")
    end

    private

    def store = settings.store

    def token_ok?
      given = request.env["HTTP_X_GALLERY_TOKEN"].to_s
      expected = settings.token.to_s
      given.bytesize == expected.bytesize &&
        OpenSSL.fixed_length_secure_compare(given, expected)
    end

    # A page on another site can reach a local port, so anything that arrives
    # claiming a different origin is turned away. Requests with no origin at
    # all (curl, say) still need the token.
    def origin_ok?
      origin = request.env["HTTP_ORIGIN"]
      return true if origin.nil? || origin.empty?

      URI.parse(origin).host == request.host
    rescue URI::InvalidURIError
      false
    end

    def json_response
      content_type :json
      JSON.generate("state" => store.state, "problems" => settings.health.problems.map(&:to_h))
    end

    def json_error(message) = JSON.generate("error" => message)

    def read_json
      raw = request.body.read
      raise InvalidRequest, "that request had no body" if raw.strip.empty?

      parsed = JSON.parse(raw)
      raise InvalidRequest, "that request was not an object" unless parsed.is_a?(Hash)

      parsed
    end

    def field(source, name, allow_empty: false)
      value = source[name]
      raise InvalidRequest, "#{name} is missing" if value.nil?
      raise InvalidRequest, "#{name} is empty" if !allow_empty && value.to_s.strip.empty?

      value.to_s
    end

    def array_field(source, name)
      value = source[name]
      raise InvalidRequest, "#{name} must be a list" unless value.is_a?(Array)

      value.map(&:to_s)
    end

    # Uploads are copied somewhere outside the repo before anything looks at
    # them, and that copy is thrown away whatever happens next.
    def stage(uploads)
      Dir.mktmpdir("gallery-manager-upload") do |staging|
        paths = uploads.each_with_index.map do |upload, index|
          tempfile = upload[:tempfile] || upload["tempfile"]
          raise InvalidRequest, "that upload arrived empty" if tempfile.nil?

          path = File.join(staging, staged_name(upload, index))
          FileUtils.cp(tempfile.path, path)
          path
        end
        yield paths
      end
    end

    def staged_name(upload, index)
      given = File.basename((upload[:filename] || upload["filename"]).to_s)
      cleaned = given.gsub(/[^A-Za-z0-9._-]/, "_").delete_prefix(".")
      cleaned.empty? ? "dropped-#{index}.jpg" : "#{index}-#{cleaned}"
    end

    # Serves photos and thumbnails, and nothing else in the repo.
    def serve_asset(path)
      relative = Pathname("assets").join(path).cleanpath.to_s
      halt 404, json_error("not found") unless relative.match?(SERVABLE)

      file = store.repo.root.join(relative)
      halt 404, json_error("not found") unless file.file?

      cache_control :no_store
      send_file(file)
    end
  end
end
