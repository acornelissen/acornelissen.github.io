require "pathname"

module GalleryManager
  Error = Class.new(StandardError)
  # Raised when a request cannot be honoured. Never leaks a filesystem path the
  # caller did not already know about.
  InvalidRequest = Class.new(Error)

  # Where things live inside the site repo, and the gatekeeper for anything
  # that came in over HTTP. Nothing client-supplied becomes a path without
  # passing through here first.
  class Repo
    PHOTO_NAME = /\A\d{2}\.jpg\z/.freeze
    # Gallery directories and URLs are confined to the photography tree.
    IMAGE_ROOT = "assets/ph".freeze
    PAGE_ROOT = "ph".freeze
    # A gallery's path segment, e.g. "mf/street".
    SLUG = %r{\A[a-z0-9]+(?:[-_][a-z0-9]+)*(?:/[a-z0-9]+(?:[-_][a-z0-9]+)*)*\z}.freeze

    attr_reader :root

    def initialize(root)
      @root = Pathname(root).expand_path
    end

    def galleries_path = root.join("_data/galleries.yml")

    def document = GalleryDocument.load_file(galleries_path)

    def write_document(document) = document.write(galleries_path)

    # "assets/ph/mf/misc" -- relative, because optimize-images wants it that way.
    def relative_image_dir(gallery)
      path = gallery.dir.to_s.delete_prefix("/").chomp("/")
      confine!(path, "#{IMAGE_ROOT}/", "gallery directory")
    end

    def relative_thumb_dir(gallery)
      relative_image_dir(gallery).sub(%r{\Aassets/}, "assets/thumbs/")
    end

    def relative_page_dir(gallery)
      url = gallery.url.to_s
      raise InvalidRequest, "gallery url must end in .html" unless url.end_with?(".html")

      confine!(url.delete_prefix("/").delete_suffix(".html"), "#{PAGE_ROOT}/", "gallery url")
    end

    def image_dir(gallery) = root.join(relative_image_dir(gallery))
    def thumb_dir(gallery) = root.join(relative_thumb_dir(gallery))
    def page_dir(gallery) = root.join(relative_page_dir(gallery))

    def image_path(gallery, name) = image_dir(gallery).join(photo_name!(name))
    def thumb_path(gallery, name) = thumb_dir(gallery).join(photo_name!(name))

    def stub_path(gallery, name)
      page_dir(gallery).join(photo_name!(name).sub(/\.jpg\z/, ".md"))
    end

    # The photos actually on disk, in display order. Disk is the source of
    # truth for what exists; galleries.yml only says what the captions are.
    def photos_on_disk(gallery)
      Dir.glob(image_dir(gallery).join("*.jpg")).map { File.basename(_1) }.sort
    end

    def photo_name!(name)
      name = name.to_s
      return name if name.match?(PHOTO_NAME)

      raise InvalidRequest, "#{name.inspect} is not a gallery photo name"
    end

    def slug!(slug)
      slug = slug.to_s
      return slug if slug.match?(SLUG)

      raise InvalidRequest, "#{slug.inspect} is not a usable gallery path"
    end

    private

    # Rejects anything that escapes its root, whether by traversal or by simply
    # pointing somewhere else in the repo.
    def confine!(path, prefix, description)
      cleaned = Pathname(path).cleanpath.to_s
      unless cleaned.start_with?(prefix) && !cleaned.include?("..")
        raise InvalidRequest, "#{description} must live under #{prefix}"
      end

      cleaned
    end
  end
end
