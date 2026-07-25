require_relative "test_helper"

# Photo order on this site is filename order, so reordering means renaming a
# run of files along with their thumbnails and generated page stubs, and
# rewriting the caption keys to match. These tests pin that behaviour down.
class ReorderTest < Minitest::Test
  include FixtureHelpers

  def test_renumbers_files_into_the_requested_order
    store.reorder_photos("mf-misc", %w[03.jpg 01.jpg 02.jpg])

    assert_equal %w[01.jpg 02.jpg 03.jpg], photo_names("mf-misc")
    assert_equal "jpeg 03.jpg", @fixture.root.join(dir_of("mf-misc"), "01.jpg").read
    assert_equal "jpeg 01.jpg", @fixture.root.join(dir_of("mf-misc"), "02.jpg").read
    assert_equal "jpeg 02.jpg", @fixture.root.join(dir_of("mf-misc"), "03.jpg").read
  end

  def test_moves_thumbnails_with_their_photos
    store.reorder_photos("mf-misc", %w[03.jpg 01.jpg 02.jpg])

    assert_equal %w[01.jpg 02.jpg 03.jpg], thumb_names("mf-misc")
    assert_equal "thumb 03.jpg", @fixture.root.join(dir_of("mf-misc").sub("assets/", "assets/thumbs/"), "01.jpg").read
  end

  def test_captions_follow_their_photos
    store.reorder_photos("mf-misc", %w[03.jpg 01.jpg 02.jpg])

    assert_equal({ "01.jpg" => "Three [Hasselblad]",
                   "02.jpg" => "One [Pentax 67 - HP5]",
                   "03.jpg" => "Two" }, captions_of("mf-misc"))
  end

  def test_the_cover_follows_its_photo
    store.reorder_photos("mf-misc", %w[03.jpg 01.jpg 02.jpg])

    # 01.jpg was the cover and is now 02.jpg.
    assert_equal "02.jpg", gallery_record("mf-misc").cover
  end

  def test_page_stubs_are_regenerated_for_the_new_names
    store.reorder_photos("mf-misc", %w[03.jpg 01.jpg 02.jpg])

    assert_equal %w[01.md 02.md 03.md], stub_names("mf-misc")
    assert_equal "01.jpg", stub_photo("mf-misc", "01.md")
  end

  def test_records_dimensions_afterwards
    subject = store
    subject.reorder_photos("mf-misc", %w[03.jpg 01.jpg 02.jpg])

    assert scripts.called?(:record_dimensions)
  end

  def test_a_no_op_reorder_leaves_the_file_untouched
    subject = store
    before = @fixture.yaml_text

    subject.reorder_photos("mf-misc", %w[01.jpg 02.jpg 03.jpg])

    assert_equal before, @fixture.yaml_text
    assert_equal %w[01.jpg 02.jpg 03.jpg], photo_names("mf-misc")
  end

  def test_reversing_a_gallery_swaps_every_file_without_losing_one
    store.reorder_photos("mf-misc", %w[03.jpg 02.jpg 01.jpg])

    assert_equal %w[01.jpg 02.jpg 03.jpg], photo_names("mf-misc")
    assert_equal "jpeg 03.jpg", @fixture.root.join(dir_of("mf-misc"), "01.jpg").read
    assert_equal "jpeg 01.jpg", @fixture.root.join(dir_of("mf-misc"), "03.jpg").read
  end

  def test_rejects_an_order_that_is_not_a_permutation_of_the_directory
    subject = store

    assert_raises(GalleryManager::InvalidRequest) do
      subject.reorder_photos("mf-misc", %w[01.jpg 02.jpg])
    end
    assert_raises(GalleryManager::InvalidRequest) do
      subject.reorder_photos("mf-misc", %w[01.jpg 02.jpg 03.jpg 04.jpg])
    end
    assert_raises(GalleryManager::InvalidRequest) do
      subject.reorder_photos("mf-misc", %w[01.jpg 01.jpg 02.jpg])
    end
  end

  def test_rejects_filenames_that_are_not_gallery_photos
    subject = store

    assert_raises(GalleryManager::InvalidRequest) do
      subject.reorder_photos("mf-misc", ["../../etc/passwd", "01.jpg", "02.jpg"])
    end
  end

  def test_leaves_the_gallery_untouched_when_the_order_is_rejected
    subject = store
    before = @fixture.yaml_text

    assert_raises(GalleryManager::InvalidRequest) { subject.reorder_photos("mf-misc", %w[01.jpg]) }

    assert_equal before, @fixture.yaml_text
    assert_equal %w[01.jpg 02.jpg 03.jpg], photo_names("mf-misc")
  end

  def test_rejects_an_unknown_gallery
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { subject.reorder_photos("nope", %w[01.jpg]) }
  end
end

class CaptionAndCoverTest < Minitest::Test
  include FixtureHelpers

  def test_sets_a_caption
    store.set_caption("mf-misc", "02.jpg", "Rewritten [Mamiya C220 - HP5]")

    assert_equal "Rewritten [Mamiya C220 - HP5]", captions_of("mf-misc")["02.jpg"]
  end

  def test_clears_a_caption_without_dropping_the_entry
    store.set_caption("mf-misc", "02.jpg", "")

    assert_equal "", captions_of("mf-misc")["02.jpg"]
    assert_includes captions_of("mf-misc").keys, "02.jpg"
  end

  def test_captions_keep_their_order_when_one_changes
    store.set_caption("mf-misc", "01.jpg", "Changed")

    assert_equal %w[01.jpg 02.jpg 03.jpg], captions_of("mf-misc").keys
  end

  def test_a_caption_change_runs_no_scripts
    subject = store
    subject.set_caption("mf-misc", "01.jpg", "Changed")

    assert_empty scripts.calls
  end

  def test_rejects_a_caption_for_a_photo_that_is_not_there
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { subject.set_caption("mf-misc", "09.jpg", "No") }
  end

  def test_sets_the_cover
    store.set_cover("mf-misc", "03.jpg")

    assert_equal "03.jpg", gallery_record("mf-misc").cover
  end

  def test_rejects_a_cover_that_is_not_in_the_gallery
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { subject.set_cover("mf-misc", "09.jpg") }
  end
end

class DeleteTest < Minitest::Test
  include FixtureHelpers

  def test_removes_the_image_thumbnail_stub_and_caption
    store.delete_photo("mf-misc", "02.jpg")

    assert_equal %w[01.jpg 02.jpg], photo_names("mf-misc")
    assert_equal %w[01.jpg 02.jpg], thumb_names("mf-misc")
    assert_equal %w[01.md 02.md], stub_names("mf-misc")
    assert_equal 2, captions_of("mf-misc").size
  end

  def test_closes_the_gap_by_renumbering
    store.delete_photo("mf-misc", "01.jpg")

    assert_equal "jpeg 02.jpg", @fixture.root.join(dir_of("mf-misc"), "01.jpg").read
    assert_equal "jpeg 03.jpg", @fixture.root.join(dir_of("mf-misc"), "02.jpg").read
    assert_equal({ "01.jpg" => "Two", "02.jpg" => "Three [Hasselblad]" }, captions_of("mf-misc"))
  end

  def test_hands_the_cover_to_the_first_photo_when_the_cover_is_deleted
    store.delete_photo("mf-misc", "01.jpg")

    assert_equal "01.jpg", gallery_record("mf-misc").cover
  end

  def test_keeps_the_cover_on_the_same_photo_when_another_is_deleted
    store(sample_galleries).delete_photo("mf-portraits", "01.jpg")

    # 02.jpg was the cover and became 01.jpg.
    assert_equal "01.jpg", gallery_record("mf-portraits").cover
    assert_equal "Beta", captions_of("mf-portraits")["01.jpg"]
  end

  def test_leaves_no_cover_when_the_last_photo_goes
    store.delete_photo("lf-misc", "01.jpg")

    assert_empty photo_names("lf-misc")
    assert_empty captions_of("lf-misc")
    assert_nil gallery_record("lf-misc").cover
  end

  def test_rejects_a_photo_that_is_not_there
    subject = store

    assert_raises(GalleryManager::InvalidRequest) { subject.delete_photo("mf-misc", "09.jpg") }
  end

  def test_rejects_a_traversing_filename
    subject = store

    assert_raises(GalleryManager::InvalidRequest) do
      subject.delete_photo("mf-misc", "../../_data/galleries.yml")
    end
    assert_path_exists @fixture.galleries_yml
  end
end

class AddTest < Minitest::Test
  include FixtureHelpers

  def test_adds_a_dropped_file_as_the_next_number
    subject = store
    subject.add_photos("mf-misc", [dropped_file])

    assert_equal %w[01.jpg 02.jpg 03.jpg 04.jpg], photo_names("mf-misc")
    assert_equal "", captions_of("mf-misc")["04.jpg"]
  end

  def test_generates_the_new_photos_page
    subject = store
    subject.add_photos("mf-misc", [dropped_file])

    assert_equal %w[01.md 02.md 03.md 04.md], stub_names("mf-misc")
  end

  def test_runs_the_scripts_once_for_the_whole_batch
    subject = store
    subject.add_photos("mf-misc", [dropped_file("a.jpg"), dropped_file("b.jpg")])

    assert_equal %w[01.jpg 02.jpg 03.jpg 04.jpg 05.jpg], photo_names("mf-misc")
    assert_equal 1, scripts.calls.count { _1.first == :generate_photo_pages }
    assert_equal 1, scripts.calls.count { _1.first == :record_dimensions }
  end

  def test_gives_an_empty_gallery_its_first_photo_and_a_cover
    subject = store
    subject.delete_photo("lf-misc", "01.jpg")
    subject.add_photos("lf-misc", [dropped_file])

    assert_equal %w[01.jpg], photo_names("lf-misc")
    assert_equal "01.jpg", gallery_record("lf-misc").cover
  end

  def test_rejects_a_file_that_is_not_a_jpeg
    subject = store
    not_an_image = @fixture.root.join("tmp/note.jpg")
    FileUtils.mkdir_p(File.dirname(not_an_image))
    File.write(not_an_image, "just text")

    assert_raises(GalleryManager::InvalidRequest) { subject.add_photos("mf-misc", [not_an_image]) }
    assert_equal %w[01.jpg 02.jpg 03.jpg], photo_names("mf-misc")
  end
end

class MoveTest < Minitest::Test
  include FixtureHelpers

  def test_moves_a_photo_to_the_end_of_another_gallery
    store.move_photo("mf-misc", "lf-misc", "02.jpg")

    assert_equal %w[01.jpg 02.jpg], photo_names("mf-misc")
    assert_equal %w[01.jpg 02.jpg], photo_names("lf-misc")
    assert_equal "jpeg 02.jpg", @fixture.root.join(dir_of("lf-misc"), "02.jpg").read
  end

  def test_carries_the_caption_across
    store.move_photo("mf-misc", "lf-misc", "02.jpg")

    assert_equal "Two", captions_of("lf-misc")["02.jpg"]
    refute_includes captions_of("mf-misc").values, "Two"
  end

  def test_renumbers_the_source_gallery_behind_it
    store.move_photo("mf-misc", "lf-misc", "01.jpg")

    assert_equal({ "01.jpg" => "Two", "02.jpg" => "Three [Hasselblad]" }, captions_of("mf-misc"))
    assert_equal "jpeg 02.jpg", @fixture.root.join(dir_of("mf-misc"), "01.jpg").read
  end

  def test_brings_the_thumbnail_and_makes_a_page
    store.move_photo("mf-misc", "lf-misc", "02.jpg")

    assert_equal %w[01.jpg 02.jpg], thumb_names("lf-misc")
    assert_equal %w[01.md 02.md], stub_names("lf-misc")
    assert_equal "02.jpg", stub_photo("lf-misc", "02.md")
  end

  def test_rejects_a_move_into_the_same_gallery
    subject = store

    assert_raises(GalleryManager::InvalidRequest) do
      subject.move_photo("mf-misc", "mf-misc", "02.jpg")
    end
  end

  def test_leaves_the_photo_in_place_when_the_destination_is_unknown
    subject = store

    assert_raises(GalleryManager::InvalidRequest) do
      subject.move_photo("mf-misc", "nope", "02.jpg")
    end
    assert_equal %w[01.jpg 02.jpg 03.jpg], photo_names("mf-misc")
  end
end
