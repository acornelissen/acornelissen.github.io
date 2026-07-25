require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "pathname"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

REAL_REPO = Pathname(File.expand_path("../../..", __dir__))

require "gallery_data"
require "repo"
require "scripts"
require "store"
require "health"

# Builds a throwaway repo that looks enough like the real one for the store to
# work on: a galleries.yml, the JPEGs it describes, their thumbnails, and the
# generated page stubs. Files hold placeholder text; nothing here needs real
# image data.
class FixtureRepo
  attr_reader :root

  def initialize
    @root = Pathname(Dir.mktmpdir("gallery-manager-test"))
  end

  # galleries: [{id:, url:, title:, section:, dir:, cover:, captions: {}}]
  # Photos come from each gallery's caption keys unless :photos is given.
  def build(galleries)
    write_yaml(galleries)
    galleries.each do |gallery|
      (gallery[:photos] || gallery[:captions].keys).each { |name| add_photo(gallery, name) }
    end
    install_scripts
    self
  end

  # generate-photo-pages resolves paths from its own location, so the fixture
  # gets a real copy of it. It is plain Ruby with no image tools behind it,
  # which means tests exercise the real script rather than a stand-in.
  def install_scripts
    FileUtils.mkdir_p(root.join("bin"))
    FileUtils.cp(REAL_REPO.join("bin/generate-photo-pages"), root.join("bin"))
    FileUtils.chmod(0o755, root.join("bin/generate-photo-pages"))
  end

  def add_photo(gallery, name)
    write(image_path(gallery, name), "jpeg #{name}")
    write(thumb_path(gallery, name), "thumb #{name}")
    write(stub_path(gallery, name), stub_body(gallery, name))
  end

  def image_path(gallery, name) = root.join(gallery[:dir].delete_prefix("/"), name)

  def thumb_path(gallery, name)
    root.join(gallery[:dir].delete_prefix("/").sub("assets/", "assets/thumbs/"), name)
  end

  def stub_path(gallery, name)
    root.join(gallery[:url].delete_prefix("/").delete_suffix(".html"),
              name.sub(/\.jpg\z/, ".md"))
  end

  def stub_body(gallery, name)
    "---\nlayout: photo\ngallery_id: #{gallery[:id]}\nphoto: \"#{name}\"\n---\n"
  end

  def galleries_yml = root.join("_data/galleries.yml")

  def yaml_text = galleries_yml.read

  def write_yaml(galleries)
    write(galleries_yml, "# Photo galleries, in display order.\n" +
                         galleries.map { |gallery| gallery_yaml(gallery) }.join)
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def destroy = FileUtils.remove_entry(root)

  private

  def gallery_yaml(gallery)
    lines = +"- id: #{gallery[:id]}\n  url: #{gallery[:url]}\n  title: #{gallery[:title]}\n"
    lines << "  section: #{gallery[:section]}\n  dir: #{gallery[:dir]}\n"
    lines << "  cover: \"#{gallery[:cover]}\"\n"
    return lines << "  captions: {}\n" if gallery[:captions].empty?

    lines << "  captions:\n"
    gallery[:captions].each { |name, caption| lines << "    \"#{name}\": \"#{caption}\"\n" }
    lines
  end
end

# Everything that shells out to sips is faked; generate-photo-pages is left
# real, because it is pure Ruby and its behaviour is part of what is under test.
class TestScripts < GalleryManager::Scripts
  attr_reader :calls

  def initialize(repo)
    super
    @calls = []
  end

  def add_photo(source, gallery_dir)
    @calls << [:add_photo, source.to_s, gallery_dir.to_s]
    name = next_free_name(repo.root.join(gallery_dir))
    FileUtils.cp(source, repo.root.join(gallery_dir, name))
    thumb = repo.root.join(gallery_dir.sub("assets/", "assets/thumbs/"), name)
    FileUtils.mkdir_p(File.dirname(thumb))
    FileUtils.cp(source, thumb)
    name
  end

  def record_dimensions = @calls << [:record_dimensions]

  def build_thumbs = @calls << [:build_thumbs]

  def generate_photo_pages
    @calls << [:generate_photo_pages]
    super
  end

  def called?(name) = calls.any? { _1.first == name }

  private

  def next_free_name(dir)
    (1..99).each do |n|
      name = format("%02d.jpg", n)
      return name unless File.exist?(File.join(dir, name))
    end
    raise "no free slot in #{dir}"
  end
end

module FixtureHelpers
  attr_reader :scripts

  # Two galleries in one section and one in another: enough to cover ordering,
  # moves between galleries, and section grouping.
  def sample_galleries
    [
      { id: "mf-misc", url: "/ph/mf/misc.html", title: "Random miscellany",
        section: "Medium format", dir: "/assets/ph/mf/misc/", cover: "01.jpg",
        captions: { "01.jpg" => "One [Pentax 67 - HP5]", "02.jpg" => "Two",
                    "03.jpg" => "Three [Hasselblad]" } },
      { id: "mf-portraits", url: "/ph/mf/portraits.html", title: "Portraits",
        section: "Medium format", dir: "/assets/ph/mf/portraits/", cover: "02.jpg",
        captions: { "01.jpg" => "Alpha", "02.jpg" => "Beta" } },
      { id: "lf-misc", url: "/ph/lf/misc.html", title: "Random miscellany",
        section: "Large format", dir: "/assets/ph/lf/misc/", cover: "01.jpg",
        captions: { "01.jpg" => "Solo" } }
    ]
  end

  def fixture(galleries = sample_galleries)
    @fixture ||= FixtureRepo.new.build(galleries)
  end

  def store(galleries = sample_galleries)
    fixture(galleries)
    repo = GalleryManager::Repo.new(@fixture.root)
    @scripts = TestScripts.new(repo)
    GalleryManager::Store.new(repo: repo, scripts: @scripts)
  end

  def document = GalleryManager::GalleryDocument.load_file(@fixture.galleries_yml)

  def gallery_record(id) = document.gallery!(id)

  def captions_of(id) = gallery_record(id).captions

  def dir_of(id) = gallery_record(id).dir.delete_prefix("/").chomp("/")

  def photo_names(id)
    Dir.glob(@fixture.root.join(dir_of(id), "*.jpg")).map { File.basename(_1) }.sort
  end

  def thumb_names(id)
    Dir.glob(@fixture.root.join(dir_of(id).sub("assets/", "assets/thumbs/"), "*.jpg"))
       .map { File.basename(_1) }.sort
  end

  def stub_names(id)
    page_dir = gallery_record(id).url.delete_prefix("/").delete_suffix(".html")
    Dir.glob(@fixture.root.join(page_dir, "*.md")).map { File.basename(_1) }.sort
  end

  def stub_photo(id, stub)
    page_dir = gallery_record(id).url.delete_prefix("/").delete_suffix(".html")
    @fixture.root.join(page_dir, stub).read[/photo: "(.+)"/, 1]
  end

  # A JPEG-signed file standing in for something dropped from Finder.
  def dropped_file(name = "drop.jpg")
    path = @fixture.root.join("tmp", name)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "\xFF\xD8\xFF\xE0dropped".b)
    path
  end

  def teardown
    @fixture&.destroy
    super
  end
end
