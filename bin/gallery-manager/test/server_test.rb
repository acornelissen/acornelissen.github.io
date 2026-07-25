require_relative "test_helper"
require "rack/test"
require "json"
require "server"

class ServerTest < Minitest::Test
  include Rack::Test::Methods
  include FixtureHelpers

  TOKEN = "test-token".freeze

  def setup
    @subject = store
    @app = GalleryManager::App.serving(store: @subject, token: TOKEN)
  end

  attr_reader :app

  def post_json(path, payload)
    post path, JSON.generate(payload),
         "CONTENT_TYPE" => "application/json", "HTTP_X_GALLERY_TOKEN" => TOKEN
  end

  def body = JSON.parse(last_response.body)

  # --- reading -----------------------------------------------------------

  def test_serves_the_page_with_the_session_token_in_it
    get "/"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, TOKEN
    assert_includes last_response["Content-Type"], "text/html"
  end

  def test_state_lists_sections_galleries_and_photos
    get "/api/state"

    assert_predicate last_response, :ok?
    assert_equal ["Medium format", "Large format"], body["state"]["sections"].map { _1["name"] }
    assert_equal %w[01.jpg 02.jpg 03.jpg],
                 body["state"]["galleries"].first["photos"].map { _1["name"] }
  end

  def test_state_carries_the_health_report
    FileUtils.rm(@fixture.root.join("assets/thumbs/ph/mf/misc/02.jpg"))

    get "/api/state"

    assert_includes body["problems"].map { _1["kind"] }, "missing_thumbnail"
  end

  def test_serves_a_gallery_photo
    get "/assets/ph/mf/misc/01.jpg"

    assert_predicate last_response, :ok?
    assert_equal "jpeg 01.jpg", last_response.body
  end

  def test_serves_a_thumbnail
    get "/assets/thumbs/ph/mf/misc/01.jpg"

    assert_predicate last_response, :ok?
    assert_equal "thumb 01.jpg", last_response.body
  end

  def test_refuses_to_serve_anything_outside_the_photo_tree
    ["/assets/../_data/galleries.yml", "/assets/ph/../../_data/galleries.yml",
     "/assets/ph/%2e%2e/%2e%2e/_data/galleries.yml", "/assets/og.png"].each do |path|
      get path

      refute_predicate last_response, :ok?, "#{path} should not be served"
    end
  end

  # --- guards ------------------------------------------------------------

  def test_a_mutation_without_the_token_is_refused
    post "/api/photos/reorder", JSON.generate(gallery: "mf-misc", names: %w[03.jpg 01.jpg 02.jpg]),
         "CONTENT_TYPE" => "application/json"

    assert_equal 403, last_response.status
    assert_equal %w[01.jpg 02.jpg 03.jpg], photo_names("mf-misc")
    assert_equal "jpeg 01.jpg", @fixture.root.join(dir_of("mf-misc"), "01.jpg").read
  end

  def test_a_mutation_with_the_wrong_token_is_refused
    post "/api/photos/reorder", JSON.generate(gallery: "mf-misc", names: %w[03.jpg 01.jpg 02.jpg]),
         "CONTENT_TYPE" => "application/json", "HTTP_X_GALLERY_TOKEN" => "guessed"

    assert_equal 403, last_response.status
  end

  def test_a_mutation_from_another_origin_is_refused
    post "/api/photos/caption", JSON.generate(gallery: "mf-misc", photo: "01.jpg", caption: "x"),
         "CONTENT_TYPE" => "application/json", "HTTP_X_GALLERY_TOKEN" => TOKEN,
         "HTTP_ORIGIN" => "https://evil.example"

    assert_equal 403, last_response.status
    assert_equal "One [Pentax 67 - HP5]", captions_of("mf-misc")["01.jpg"]
  end

  def test_a_mutation_from_the_page_itself_is_allowed
    post "/api/photos/caption", JSON.generate(gallery: "mf-misc", photo: "01.jpg", caption: "Fine"),
         "CONTENT_TYPE" => "application/json", "HTTP_X_GALLERY_TOKEN" => TOKEN,
         "HTTP_ORIGIN" => "http://example.org"

    assert_predicate last_response, :ok?
    assert_equal "Fine", captions_of("mf-misc")["01.jpg"]
  end

  # --- mutations ---------------------------------------------------------

  def test_reorders_photos_and_returns_fresh_state
    post_json "/api/photos/reorder", gallery: "mf-misc", names: %w[03.jpg 01.jpg 02.jpg]

    assert_predicate last_response, :ok?
    assert_equal "jpeg 03.jpg", @fixture.root.join(dir_of("mf-misc"), "01.jpg").read
    assert_equal "Three [Hasselblad]",
                 body["state"]["galleries"].first["photos"].first["caption"]
  end

  def test_sets_a_caption
    post_json "/api/photos/caption", gallery: "mf-misc", photo: "02.jpg", caption: "New words"

    assert_predicate last_response, :ok?
    assert_equal "New words", captions_of("mf-misc")["02.jpg"]
  end

  def test_sets_a_cover
    post_json "/api/photos/cover", gallery: "mf-misc", photo: "03.jpg"

    assert_equal "03.jpg", gallery_record("mf-misc").cover
  end

  def test_deletes_a_photo
    post_json "/api/photos/delete", gallery: "mf-misc", photo: "02.jpg"

    assert_equal %w[01.jpg 02.jpg], photo_names("mf-misc")
  end

  def test_moves_a_photo_between_galleries
    post_json "/api/photos/move", from: "mf-misc", to: "lf-misc", photo: "02.jpg"

    assert_equal %w[01.jpg 02.jpg], photo_names("mf-misc")
    assert_equal "Two", captions_of("lf-misc")["02.jpg"]
  end

  def test_uploads_dropped_photos
    post "/api/photos/add",
         { "gallery" => "mf-misc", "files" => [Rack::Test::UploadedFile.new(dropped_file, "image/jpeg")] },
         "HTTP_X_GALLERY_TOKEN" => TOKEN

    assert_predicate last_response, :ok?
    assert_equal %w[01.jpg 02.jpg 03.jpg 04.jpg], photo_names("mf-misc")
  end

  def test_refuses_an_upload_that_is_not_a_jpeg
    not_an_image = @fixture.root.join("tmp/note.jpg")
    FileUtils.mkdir_p(File.dirname(not_an_image))
    File.write(not_an_image, "just text")

    post "/api/photos/add",
         { "gallery" => "mf-misc", "files" => [Rack::Test::UploadedFile.new(not_an_image, "image/jpeg")] },
         "HTTP_X_GALLERY_TOKEN" => TOKEN

    assert_equal 422, last_response.status
    assert_equal %w[01.jpg 02.jpg 03.jpg], photo_names("mf-misc")
  end

  def test_creates_a_gallery
    post_json "/api/galleries/create",
              id: "mf-street", title: "Street", section: "Medium format", slug: "mf/street"

    assert_predicate last_response, :ok?
    assert_equal "/ph/mf/street.html", gallery_record("mf-street").url
  end

  def test_renames_a_gallery
    post_json "/api/galleries/update", gallery: "mf-misc", title: "Miscellany"

    assert_equal "Miscellany", gallery_record("mf-misc").title
  end

  def test_reorders_galleries
    post_json "/api/galleries/reorder", ids: %w[mf-portraits mf-misc lf-misc]

    assert_equal %w[mf-portraits mf-misc lf-misc], document.galleries.map(&:id)
  end

  def test_deletes_an_empty_gallery
    post_json "/api/photos/delete", gallery: "lf-misc", photo: "01.jpg"
    post_json "/api/galleries/delete", gallery: "lf-misc"

    assert_nil document.gallery("lf-misc")
  end

  def test_repairs_drift
    FileUtils.mv(@fixture.root.join("assets/ph/mf/misc/03.jpg"),
                 @fixture.root.join("assets/ph/mf/misc/08.jpg"))
    FileUtils.mv(@fixture.root.join("assets/thumbs/ph/mf/misc/03.jpg"),
                 @fixture.root.join("assets/thumbs/ph/mf/misc/08.jpg"))

    post_json "/api/repair", {}

    assert_predicate last_response, :ok?
    assert_equal %w[01.jpg 02.jpg 03.jpg], photo_names("mf-misc")
  end

  # --- failures ----------------------------------------------------------

  def test_a_rejected_request_explains_itself_without_a_stack_trace
    post_json "/api/photos/reorder", gallery: "mf-misc", names: %w[01.jpg 02.jpg]

    assert_equal 422, last_response.status
    assert_match(/must list each of the 3 photos/, body["error"])
  end

  def test_an_unknown_gallery_is_rejected
    post_json "/api/photos/caption", gallery: "nope", photo: "01.jpg", caption: "x"

    assert_equal 422, last_response.status
    assert_match(/no gallery called/, body["error"])
  end

  def test_a_missing_field_is_rejected_rather_than_guessed_at
    post_json "/api/photos/caption", gallery: "mf-misc"

    assert_equal 422, last_response.status
  end

  def test_an_unknown_route_answers_in_json
    get "/api/nonsense"

    assert_equal 404, last_response.status
    assert_equal "not found", body["error"]
  end

  def test_a_script_failure_is_reported_rather_than_swallowed
    @subject.scripts.define_singleton_method(:record_dimensions) do
      raise GalleryManager::Error, "optimize-images failed: sips is not available"
    end

    post_json "/api/photos/reorder", gallery: "mf-misc", names: %w[03.jpg 01.jpg 02.jpg]

    assert_equal 500, last_response.status
    assert_match(/sips is not available/, body["error"])
  end
end
