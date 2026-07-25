require_relative "test_helper"

class CreateGalleryTest < Minitest::Test
  include FixtureHelpers

  def create(subject, **overrides)
    subject.create_gallery(**{ id: "mf-street", title: "Street",
                               section: "Medium format", slug: "mf/street" }.merge(overrides))
  end

  def test_adds_the_gallery_with_derived_url_and_directory
    create(store)

    gallery = gallery_record("mf-street")

    assert_equal "/ph/mf/street.html", gallery.url
    assert_equal "/assets/ph/mf/street/", gallery.dir
    assert_nil gallery.cover
    assert_empty gallery.captions
  end

  def test_makes_the_image_and_thumbnail_directories
    create(store)

    assert_path_exists @fixture.root.join("assets/ph/mf/street")
    assert_path_exists @fixture.root.join("assets/thumbs/ph/mf/street")
  end

  def test_places_it_after_the_last_gallery_of_its_section
    create(store)

    assert_equal %w[mf-misc mf-portraits mf-street lf-misc], document.galleries.map(&:id)
  end

  def test_a_new_section_goes_to_the_end_and_starts_a_blank_line
    create(store, id: "in-instax", section: "Instant", slug: "instant/instax")

    assert_equal %w[mf-misc mf-portraits lf-misc in-instax], document.galleries.map(&:id)
    assert_includes @fixture.yaml_text, "\n- id: in-instax\n"
  end

  def test_rejects_a_duplicate_id
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { create(subject, id: "mf-misc") }
  end

  def test_rejects_a_directory_that_is_already_in_use
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { create(subject, id: "other", slug: "mf/misc") }
  end

  def test_rejects_a_blank_title_or_section
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { create(subject, title: "  ") }
    assert_raises(GalleryManager::InvalidRequest) { create(subject, section: "") }
  end

  def test_rejects_a_slug_that_tries_to_climb_out_of_the_photo_tree
    subject = store

    ["../../_data", "/etc/passwd", "mf/../../secrets", "mf/street/"].each do |slug|
      assert_raises(GalleryManager::InvalidRequest) { create(subject, slug: slug) }
    end
    refute_path_exists @fixture.root.join("secrets")
  end

  def test_rejects_an_id_that_is_not_a_plain_slug
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { create(subject, id: "../oops") }
  end
end

class UpdateGalleryTest < Minitest::Test
  include FixtureHelpers

  def test_renames_a_gallery
    store.update_gallery("mf-misc", title: "Miscellany")

    assert_equal "Miscellany", gallery_record("mf-misc").title
  end

  def test_moves_a_gallery_to_another_section
    store.update_gallery("mf-misc", section: "Large format")

    assert_equal "Large format", gallery_record("mf-misc").section
  end

  def test_leaves_the_url_and_directory_alone
    store.update_gallery("mf-misc", title: "Miscellany")

    assert_equal "/ph/mf/misc.html", gallery_record("mf-misc").url
    assert_equal "/assets/ph/mf/misc/", gallery_record("mf-misc").dir
  end

  def test_rejects_an_empty_section
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { subject.update_gallery("mf-misc", section: " ") }
  end
end

class DeleteGalleryTest < Minitest::Test
  include FixtureHelpers

  def test_refuses_while_it_still_holds_photos
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { subject.delete_gallery("mf-misc") }
    assert gallery_record("mf-misc")
  end

  def test_removes_an_empty_gallery_and_its_directories
    subject = store
    subject.delete_photo("lf-misc", "01.jpg")

    subject.delete_gallery("lf-misc")

    assert_nil document.gallery("lf-misc")
    refute_path_exists @fixture.root.join("assets/ph/lf/misc")
    refute_path_exists @fixture.root.join("ph/lf/misc")
  end
end

class ReorderGalleriesTest < Minitest::Test
  include FixtureHelpers

  def test_applies_the_new_order
    store.reorder_galleries(%w[mf-portraits mf-misc lf-misc])

    assert_equal %w[mf-portraits mf-misc lf-misc], document.galleries.map(&:id)
  end

  def test_keeps_a_blank_line_where_the_section_changes
    store.reorder_galleries(%w[lf-misc mf-misc mf-portraits])

    assert_includes @fixture.yaml_text, "\n- id: mf-misc\n"
  end

  def test_rejects_an_order_that_drops_or_repeats_a_gallery
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { subject.reorder_galleries(%w[mf-misc lf-misc]) }
    assert_raises(GalleryManager::InvalidRequest) do
      subject.reorder_galleries(%w[mf-misc mf-misc mf-portraits lf-misc])
    end
    assert_equal %w[mf-misc mf-portraits lf-misc], document.galleries.map(&:id)
  end
end

class StateTest < Minitest::Test
  include FixtureHelpers

  def test_groups_galleries_by_section_in_file_order
    sections = store.state["sections"]

    assert_equal ["Medium format", "Large format"], sections.map { _1["name"] }
    assert_equal %w[mf-misc mf-portraits], sections.first["gallery_ids"]
  end

  def test_lists_photos_from_disk_with_their_captions_and_urls
    gallery = store.state["galleries"].find { _1["id"] == "mf-misc" }

    assert_equal %w[01.jpg 02.jpg 03.jpg], gallery["photos"].map { _1["name"] }

    first = gallery["photos"].first

    assert_equal "One [Pentax 67 - HP5]", first["caption"]
    assert_equal "/assets/ph/mf/misc/01.jpg", first["image"]
    assert_equal "/assets/thumbs/ph/mf/misc/01.jpg", first["thumb"]
    assert_equal "/ph/mf/misc/01.html", first["page"]
  end

  def test_a_photo_with_no_caption_entry_still_appears
    subject = store
    @fixture.write(@fixture.root.join("assets/ph/mf/misc/04.jpg"), "jpeg 04.jpg")

    gallery = subject.state["galleries"].find { _1["id"] == "mf-misc" }

    assert_equal %w[01.jpg 02.jpg 03.jpg 04.jpg], gallery["photos"].map { _1["name"] }
    assert_equal "", gallery["photos"].last["caption"]
  end
end
