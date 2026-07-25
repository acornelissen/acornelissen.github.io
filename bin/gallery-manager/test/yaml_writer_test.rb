require_relative "test_helper"
require "gallery_data"

# The site's galleries.yml is hand-written: a header comment, blank lines
# grouping galleries, quoted filename keys. A generic YAML dumper would discard
# all of that and produce a diff touching every line, so the writer has to
# reproduce the file's own style.
class YamlWriterTest < Minitest::Test
  include FixtureHelpers

  def test_round_trips_the_real_galleries_file_byte_for_byte
    original = REAL_REPO.join("_data/galleries.yml").read

    document = GalleryManager::GalleryDocument.parse(original)

    assert_equal original, document.to_yaml
  end

  # Counts and titles are Albert's to change, so this checks the parser against
  # whatever the file happens to say rather than against a snapshot of it.
  def test_parses_every_gallery_in_the_real_file
    text = REAL_REPO.join("_data/galleries.yml").read

    document = GalleryManager::GalleryDocument.parse(text)

    refute_empty document.galleries
    assert_equal text.scan(/^- id:/).length, document.galleries.length
    assert_equal document.galleries.map(&:section).uniq, document.sections
    assert(document.galleries.all? { |gallery| gallery.id && gallery.url && gallery.dir })
    assert(document.galleries.all? { |gallery| gallery.captions.is_a?(Hash) })
  end

  def test_keeps_the_header_comment
    document = GalleryManager::GalleryDocument.parse(<<~YAML)
      # A comment.
      # Another line.
      - id: one
        url: /ph/one.html
        title: One
        section: Section
        dir: /assets/ph/one/
        cover: "01.jpg"
        captions:
          "01.jpg": "Caption"
    YAML

    assert_includes document.to_yaml, "# A comment.\n# Another line.\n- id: one\n"
  end

  def test_preserves_which_galleries_had_a_blank_line_before_them
    source = <<~YAML
      - id: one
        url: /ph/one.html
        title: One
        section: A
        dir: /assets/ph/one/
        cover: "01.jpg"
        captions:
          "01.jpg": "Caption"
      - id: two
        url: /ph/two.html
        title: Two
        section: A
        dir: /assets/ph/two/
        cover: "01.jpg"
        captions:
          "01.jpg": "Caption"

      - id: three
        url: /ph/three.html
        title: Three
        section: B
        dir: /assets/ph/three/
        cover: "01.jpg"
        captions:
          "01.jpg": "Caption"
    YAML

    assert_equal source, GalleryManager::GalleryDocument.parse(source).to_yaml
  end

  def test_writes_a_caption_change_without_touching_other_lines
    source = fixture.yaml_text
    document = GalleryManager::GalleryDocument.parse(source)

    document.gallery("mf-misc").captions["02.jpg"] = "Rewritten"

    assert_equal source.sub('"02.jpg": "Two"', '"02.jpg": "Rewritten"'), document.to_yaml
  end

  def test_quotes_captions_containing_double_quotes_and_backslashes
    document = GalleryManager::GalleryDocument.parse(fixture.yaml_text)
    document.gallery("mf-misc").captions["01.jpg"] = 'He said "hi" \\ then left'

    reparsed = GalleryManager::GalleryDocument.parse(document.to_yaml)

    assert_equal 'He said "hi" \\ then left', reparsed.gallery("mf-misc").captions["01.jpg"]
  end

  def test_leaves_accented_characters_literal
    document = GalleryManager::GalleryDocument.parse(fixture.yaml_text)
    document.gallery("mf-misc").captions["01.jpg"] = "Chloë"

    assert_includes document.to_yaml, '"01.jpg": "Chloë"'
  end

  def test_writes_an_empty_caption_as_an_empty_string
    document = GalleryManager::GalleryDocument.parse(fixture.yaml_text)
    document.gallery("mf-misc").captions["01.jpg"] = ""

    assert_includes document.to_yaml, '"01.jpg": ""'
    assert_equal "", GalleryManager::GalleryDocument.parse(document.to_yaml)
                                                   .gallery("mf-misc").captions["01.jpg"]
  end

  def test_quotes_titles_that_would_not_survive_as_plain_scalars
    document = GalleryManager::GalleryDocument.parse(fixture.yaml_text)
    document.gallery("mf-misc").title = "Portraits: close up"

    reparsed = GalleryManager::GalleryDocument.parse(document.to_yaml)

    assert_equal "Portraits: close up", reparsed.gallery("mf-misc").title
  end

  # A gallery titled for the day it was shot reads as a date to YAML, which
  # refuses to build one unless asked. Losing the file over a title is not on.
  def test_reads_a_date_shaped_title_and_writes_it_back_as_text
    source = <<~YAML
      - id: one
        url: /ph/one.html
        title: 2024-01-05
        section: Section
        dir: /assets/ph/one/
        cover: "01.jpg"
        captions:
          "01.jpg": "Caption"
    YAML

    document = GalleryManager::GalleryDocument.parse(source)

    assert_includes document.to_yaml, 'title: "2024-01-05"'
    assert_equal "2024-01-05",
                 GalleryManager::GalleryDocument.parse(document.to_yaml).gallery!("one").title
  end

  def test_writes_a_gallery_with_no_photos_as_an_empty_map
    document = GalleryManager::GalleryDocument.parse(fixture.yaml_text)
    document.gallery("mf-misc").captions.clear

    assert_includes document.to_yaml, "  captions: {}\n"
    assert_empty GalleryManager::GalleryDocument.parse(document.to_yaml)
                                                .gallery("mf-misc").captions
  end

  def test_new_galleries_start_a_blank_line_when_the_section_changes
    document = GalleryManager::GalleryDocument.parse(fixture.yaml_text)

    document.add(GalleryManager::Gallery.new(
                   id: "in-instax", url: "/ph/instant/instax.html", title: "Instax",
                   section: "Instant", dir: "/assets/ph/instant/instax/", cover: nil,
                   captions: {}
                 ))

    assert_includes document.to_yaml, "\n- id: in-instax\n"
  end
end
