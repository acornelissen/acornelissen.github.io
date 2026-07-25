require "yaml"

require "repo"
require "store"

module GalleryManager
  # Reports where galleries.yml, the images, their thumbnails, the recorded
  # dimensions and the generated pages have drifted apart -- usually because
  # something was changed by hand outside this tool.
  class Health
    Problem = Struct.new(:kind, :gallery_id, :detail, :fixable, keyword_init: true) do
      def to_h = { "kind" => kind, "gallery" => gallery_id, "detail" => detail, "fixable" => fixable }
    end

    def initialize(repo:, store:)
      @repo = repo
      @store = store
    end

    def problems
      document = repo.document
      dimensions = recorded_dimensions

      document.galleries.flat_map do |gallery|
        next [missing_directory(gallery)] unless repo.image_dir(gallery).exist?

        photos = repo.photos_on_disk(gallery)
        captions(gallery, photos) + thumbnails(gallery, photos) + pages(gallery, photos) +
          dimensions_for(gallery, photos, dimensions) + cover(gallery, photos) +
          numbering(gallery, photos)
      end.compact
    end

    # Runs the scripts that resolve the fixable problems, closes any gaps in
    # the numbering, and gives every photo a caption entry to fill in. What the
    # caption should say, and which photo makes the best cover, are left alone:
    # those are judgement calls, not something a repair pass can guess.
    def repair
      store.scripts.build_thumbs
      close_numbering_gaps
      align_caption_entries
      store.scripts.generate_photo_pages
      store.scripts.record_dimensions
      store.state
    end

    private

    def close_numbering_gaps
      repo.document.galleries.each do |gallery|
        photos = repo.photos_on_disk(gallery)
        next if photos == sequential(photos.length)

        store.reorder_photos(gallery.id, photos)
      end
    end

    # Puts the caption keys back in step with the files: one entry per photo,
    # in display order, empty where there is nothing to say. A caption whose
    # photo has gone is kept at the end while its name is still free; once
    # closing a gap hands that name to another photo the text goes, because
    # leaving it would caption the wrong picture. The orphan is reported before
    # any of this runs, so there is a chance to rescue the words first.
    def align_caption_entries
      document = repo.document
      document.galleries.each do |gallery|
        photos = repo.photos_on_disk(gallery)
        known = gallery.captions
        aligned = photos.to_h { |name| [name, known.fetch(name, "")] }
        gallery.captions = aligned.merge(known.reject { |name, _| photos.include?(name) })
      end
      repo.write_document(document)
    end

    attr_reader :repo, :store

    def missing_directory(gallery)
      problem("missing_directory", gallery, "#{gallery.dir} does not exist", fixable: false)
    end

    def captions(gallery, photos)
      orphans = gallery.captions.keys - photos
      missing = photos - gallery.captions.keys

      orphans.map { problem("orphan_caption", gallery, "#{_1} has a caption but no photo") } +
        missing.map { problem("missing_caption", gallery, "#{_1} has no caption entry") }
    end

    def thumbnails(gallery, photos)
      photos.reject { repo.thumb_path(gallery, _1).exist? }
            .map { problem("missing_thumbnail", gallery, "#{_1} has no thumbnail", fixable: true) }
    end

    def pages(gallery, photos)
      page_dir = repo.page_dir(gallery)
      stubs = page_dir.exist? ? Dir.glob(page_dir.join("*.md")).map { File.basename(_1) }.sort : []
      expected = photos.map { _1.sub(/\.jpg\z/, ".md") }

      (expected - stubs).map { problem("missing_page", gallery, "#{_1} has no page", fixable: true) } +
        (stubs - expected).map { problem("orphan_page", gallery, "#{_1} has no photo", fixable: true) }
    end

    def dimensions_for(gallery, photos, dimensions)
      photos.reject { dimensions.key?("#{gallery.dir}#{_1}") }
            .map { problem("missing_dimensions", gallery, "#{_1} has no recorded size", fixable: true) }
    end

    def cover(gallery, photos)
      return [problem("missing_cover", gallery, "no cover chosen")] if gallery.cover.nil? && photos.any?
      return [] if gallery.cover.nil? || photos.include?(gallery.cover)

      [problem("absent_cover", gallery, "the cover #{gallery.cover} is not in the gallery")]
    end

    def numbering(gallery, photos)
      return [] if photos == sequential(photos.length)

      [problem("numbering_gap", gallery, "photos are not numbered 01 upwards", fixable: true)]
    end

    def sequential(count) = (1..count).map { format("%02d.jpg", _1) }

    def recorded_dimensions
      path = repo.root.join("_data/image_dims.yml")
      return {} unless path.exist?

      YAML.safe_load(path.read) || {}
    rescue Psych::Exception
      {}
    end

    def problem(kind, gallery, detail, fixable: false)
      Problem.new(kind: kind, gallery_id: gallery.id, detail: detail, fixable: fixable)
    end
  end
end
