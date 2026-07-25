require_relative "test_helper"

# Drift happens when photos are moved around by hand outside this tool. The
# health check is what tells you about it before the site does.
class HealthTest < Minitest::Test
  include FixtureHelpers

  def health(subject = store)
    GalleryManager::Health.new(repo: subject.repo, store: subject)
  end

  def kinds(problems) = problems.map(&:kind).sort

  def test_a_consistent_repo_reports_nothing
    subject = store
    record_all_dimensions

    assert_empty health(subject).problems
  end

  def test_notices_a_caption_with_no_photo
    subject = store
    record_all_dimensions
    FileUtils.rm(@fixture.root.join("assets/ph/mf/misc/03.jpg"))
    FileUtils.rm(@fixture.root.join("assets/thumbs/ph/mf/misc/03.jpg"))
    FileUtils.rm(@fixture.root.join("ph/mf/misc/03.md"))

    problems = health(subject).problems

    assert_includes kinds(problems), "orphan_caption"
    assert_equal "mf-misc", problems.first.gallery_id
  end

  def test_notices_a_photo_with_no_caption
    subject = store
    add_loose_photo
    record_all_dimensions

    assert_includes kinds(health(subject).problems), "missing_caption"
  end

  def test_notices_a_missing_thumbnail
    subject = store
    record_all_dimensions
    FileUtils.rm(@fixture.root.join("assets/thumbs/ph/mf/misc/02.jpg"))

    problems = health(subject).problems

    assert_includes kinds(problems), "missing_thumbnail"
    assert problems.find { _1.kind == "missing_thumbnail" }.fixable
  end

  def test_notices_a_missing_page_and_an_orphaned_one
    subject = store
    record_all_dimensions
    FileUtils.rm(@fixture.root.join("ph/mf/misc/02.md"))
    @fixture.write(@fixture.root.join("ph/mf/misc/09.md"), "---\n---\n")

    assert_includes kinds(health(subject).problems), "missing_page"
    assert_includes kinds(health(subject).problems), "orphan_page"
  end

  def test_notices_unrecorded_dimensions
    subject = store

    assert_includes kinds(health(subject).problems), "missing_dimensions"
  end

  def test_notices_a_cover_that_is_not_in_the_gallery
    subject = store
    record_all_dimensions
    subject.repo.write_document(document.tap { _1.gallery!("mf-misc").cover = "09.jpg" })

    assert_includes kinds(health(subject).problems), "absent_cover"
  end

  def test_notices_a_gap_in_the_numbering
    subject = store
    record_all_dimensions
    FileUtils.mv(@fixture.root.join("assets/ph/mf/misc/02.jpg"),
                 @fixture.root.join("assets/ph/mf/misc/07.jpg"))

    assert_includes kinds(health(subject).problems), "numbering_gap"
  end

  def test_notices_a_gallery_whose_directory_has_gone
    subject = store
    record_all_dimensions
    FileUtils.rm_rf(@fixture.root.join("assets/ph/lf/misc"))

    problems = health(subject).problems

    assert_includes kinds(problems), "missing_directory"
    assert_equal "lf-misc", problems.find { _1.kind == "missing_directory" }.gallery_id
  end

  def test_repair_closes_a_numbering_gap_and_regenerates_pages
    subject = store
    FileUtils.mv(@fixture.root.join("assets/ph/mf/misc/03.jpg"),
                 @fixture.root.join("assets/ph/mf/misc/08.jpg"))
    FileUtils.mv(@fixture.root.join("assets/thumbs/ph/mf/misc/03.jpg"),
                 @fixture.root.join("assets/thumbs/ph/mf/misc/08.jpg"))

    health(subject).repair

    assert_equal %w[01.jpg 02.jpg 03.jpg], photo_names("mf-misc")
    assert_equal %w[01.md 02.md 03.md], stub_names("mf-misc")
    assert scripts.called?(:build_thumbs)
  end

  def test_repair_gives_a_loose_photo_an_empty_caption_entry_to_fill_in
    subject = store
    add_loose_photo

    health(subject).repair

    assert_equal "", captions_of("mf-misc")["04.jpg"]
    assert_equal %w[01.jpg 02.jpg 03.jpg 04.jpg], captions_of("mf-misc").keys
  end

  def test_repair_does_not_choose_captions_or_covers
    subject = store
    add_loose_photo

    health(subject).repair

    assert_equal "One [Pentax 67 - HP5]", captions_of("mf-misc")["01.jpg"]
    assert_equal "01.jpg", gallery_record("mf-misc").cover
  end

  def test_repair_never_re_attaches_a_caption_to_a_different_photo
    subject = store
    FileUtils.rm(@fixture.root.join("assets/ph/mf/misc/02.jpg"))
    FileUtils.rm(@fixture.root.join("assets/thumbs/ph/mf/misc/02.jpg"))

    # Closing the gap makes the old 03.jpg into 02.jpg. Its caption has to
    # travel with it rather than the vacated name keeping the text that was
    # written about the photo that is gone.
    health(subject).repair

    assert_equal({ "01.jpg" => "One [Pentax 67 - HP5]", "02.jpg" => "Three [Hasselblad]" },
                 captions_of("mf-misc"))
  end

  def test_a_caption_whose_photo_has_gone_is_reported_before_any_repair
    subject = store
    FileUtils.rm(@fixture.root.join("assets/ph/mf/misc/02.jpg"))

    orphan = health(subject).problems.find { _1.kind == "orphan_caption" }

    assert_equal "02.jpg has a caption but no photo", orphan.detail
  end

  def test_repair_keeps_an_orphaned_caption_whose_name_is_still_free
    subject = store
    document = subject.repo.document
    document.gallery!("mf-misc").captions["09.jpg"] = "Written about a photo never added"
    subject.repo.write_document(document)

    health(subject).repair

    assert_equal "Written about a photo never added", captions_of("mf-misc")["09.jpg"]
  end

  private

  def add_loose_photo
    @fixture.write(@fixture.root.join("assets/ph/mf/misc/04.jpg"), "jpeg 04.jpg")
    @fixture.write(@fixture.root.join("assets/thumbs/ph/mf/misc/04.jpg"), "thumb 04.jpg")
    @fixture.write(@fixture.root.join("ph/mf/misc/04.md"),
                   "---\nlayout: photo\ngallery_id: mf-misc\nphoto: \"04.jpg\"\n---\n")
  end

  # Stands in for what optimize-images dims would have written.
  def record_all_dimensions
    entries = Dir.glob(@fixture.root.join("assets/ph/**/*.jpg")).map do |path|
      "\"/#{Pathname(path).relative_path_from(@fixture.root)}\": \"100x100\""
    end
    @fixture.write(@fixture.root.join("_data/image_dims.yml"), "# Generated.\n#{entries.join("\n")}\n")
  end
end
