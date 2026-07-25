require "fileutils"
require "securerandom"

require "gallery_data"
require "repo"
require "scripts"

module GalleryManager
  # Every operation the manager can perform, and the only code that changes
  # anything on disk. Each one either completes or raises, and the caller reads
  # fresh state back afterwards rather than assuming what happened.
  class Store
    JPEG_SIGNATURE = "\xFF\xD8\xFF".b.freeze
    MAX_UPLOAD_BYTES = 40 * 1024 * 1024

    attr_reader :repo, :scripts

    def initialize(repo:, scripts:)
      @repo = repo
      @scripts = scripts
    end

    # --- reading -----------------------------------------------------------

    def state
      document = repo.document
      {
        "sections" => document.sections.map do |section|
          { "name" => section,
            "gallery_ids" => document.galleries.select { _1.section == section }.map(&:id) }
        end,
        "galleries" => document.galleries.map { gallery_state(_1) }
      }
    end

    def gallery_state(gallery)
      photos = repo.photos_on_disk(gallery)
      {
        "id" => gallery.id,
        "title" => gallery.title,
        "section" => gallery.section,
        "url" => gallery.url,
        "dir" => gallery.dir,
        "cover" => gallery.cover,
        "photos" => photos.map { |name| photo_state(gallery, name) }
      }
    end

    # --- photos ------------------------------------------------------------

    # `names` is the gallery's photos in their new order. Files are renumbered
    # to match, because the site takes display order from the filenames.
    def reorder_photos(gallery_id, names)
      edit(gallery_id) do |gallery|
        renames = renumber(gallery, permutation!(gallery, names))
        next if renames.empty?

        gallery.cover = renames.fetch(gallery.cover, gallery.cover)
      end
    end

    def set_caption(gallery_id, name, text)
      edit(gallery_id, scripts: false) do |gallery|
        gallery.captions[on_disk!(gallery, name)] = text.to_s
      end
    end

    def set_cover(gallery_id, name)
      edit(gallery_id, scripts: false) do |gallery|
        gallery.cover = on_disk!(gallery, name)
      end
    end

    def delete_photo(gallery_id, name)
      edit(gallery_id) do |gallery|
        name = on_disk!(gallery, name)
        remaining = repo.photos_on_disk(gallery) - [name]
        was_cover = gallery.cover == name

        remove_files(gallery, name)
        gallery.captions.delete(name)
        renames = renumber(gallery, remaining)

        gallery.cover = was_cover ? remaining.first && "01.jpg" : renames.fetch(gallery.cover, gallery.cover)
      end
    end

    # `sources` are paths to files already staged outside the repo.
    def add_photos(gallery_id, sources)
      sources = Array(sources)
      sources.each { |source| jpeg!(source) }

      edit(gallery_id) do |gallery|
        sources.each do |source|
          name = scripts.add_photo(source, repo.relative_image_dir(gallery))
          gallery.captions[repo.photo_name!(name)] = ""
        end
        gallery.cover ||= repo.photos_on_disk(gallery).first
      end
    end

    def move_photo(source_id, destination_id, name)
      raise InvalidRequest, "a photo cannot be moved into its own gallery" if source_id == destination_id

      document = repo.document
      source = gallery!(document, source_id)
      destination = gallery!(document, destination_id)
      name = on_disk!(source, name)

      new_name = copy_into(source, destination, name)
      destination.captions[new_name] = source.caption(name)
      destination.cover ||= new_name

      remaining = repo.photos_on_disk(source) - [name]
      was_cover = source.cover == name
      remove_files(source, name)
      source.captions.delete(name)
      renames = renumber(source, remaining)
      source.cover = was_cover ? remaining.first && "01.jpg" : renames.fetch(source.cover, source.cover)

      commit(document)
    end

    # --- galleries ---------------------------------------------------------

    def create_gallery(id:, title:, section:, slug:)
      document = repo.document
      raise InvalidRequest, "a gallery called #{id.inspect} already exists" if document.gallery(id)
      raise InvalidRequest, "a gallery needs a title" if title.to_s.strip.empty?
      raise InvalidRequest, "a gallery needs a section" if section.to_s.strip.empty?

      slug = repo.slug!(slug)
      gallery = Gallery.new(id: identifier!(id), title: title.to_s.strip,
                            section: section.to_s.strip,
                            url: "/#{Repo::PAGE_ROOT}/#{slug}.html",
                            dir: "/#{Repo::IMAGE_ROOT}/#{slug}/", cover: nil, captions: {})

      raise InvalidRequest, "#{gallery.dir} is already in use" if repo.image_dir(gallery).exist?

      document.add(gallery, index: after_last_in_section(document, gallery.section))
      FileUtils.mkdir_p(repo.image_dir(gallery))
      FileUtils.mkdir_p(repo.thumb_dir(gallery))
      commit(document, scripts: false)
    end

    def update_gallery(gallery_id, title: nil, section: nil)
      edit(gallery_id, scripts: false) do |gallery|
        gallery.title = title.to_s.strip unless title.nil?
        unless section.nil?
          raise InvalidRequest, "a gallery needs a section" if section.to_s.strip.empty?

          gallery.section = section.to_s.strip
        end
      end
    end

    def delete_gallery(gallery_id)
      document = repo.document
      gallery = gallery!(document, gallery_id)
      photos = repo.photos_on_disk(gallery)
      unless photos.empty?
        raise InvalidRequest, "#{gallery.title} still holds #{photos.length} photos; empty it first"
      end

      document.remove(gallery_id)
      [repo.image_dir(gallery), repo.thumb_dir(gallery), repo.page_dir(gallery)].each do |dir|
        FileUtils.rm_rf(dir) if dir.exist?
      end
      commit(document, scripts: false)
    end

    # `ids` is every gallery, in its new order.
    def reorder_galleries(ids)
      document = repo.document
      existing = document.galleries.map(&:id)
      unless ids.sort == existing.sort
        raise InvalidRequest, "the gallery order must list every gallery exactly once"
      end

      reordered = ids.map { |id| document.gallery!(id) }
      reordered.each_with_index do |gallery, index|
        gallery.blank_before ||= index.positive? && reordered[index - 1].section != gallery.section
      end
      document.galleries.replace(reordered)
      commit(document, scripts: false)
    end

    private

    def photo_state(gallery, name)
      { "name" => name,
        "caption" => gallery.caption(name),
        "image" => "#{gallery.dir}#{name}",
        "thumb" => "#{gallery.dir.sub('/assets/', '/assets/thumbs/')}#{name}",
        "page" => "#{gallery.url.delete_suffix('.html')}/#{name.sub(/\.jpg\z/, '.html')}" }
    end

    # Loads the document, hands one gallery to the block, then writes and runs
    # whatever the change needs. Nothing is written if the block raises.
    def edit(gallery_id, scripts: true)
      document = repo.document
      yield gallery!(document, gallery_id)
      commit(document, scripts: scripts)
    end

    def commit(document, scripts: true)
      repo.write_document(document)
      if scripts
        self.scripts.generate_photo_pages
        self.scripts.record_dimensions
      end
      state
    end

    def gallery!(document, id)
      document.gallery(id) or raise InvalidRequest, "no gallery called #{id.inspect}"
    end

    def on_disk!(gallery, name)
      name = repo.photo_name!(name)
      return name if repo.photos_on_disk(gallery).include?(name)

      raise InvalidRequest, "#{gallery.title} has no photo #{name}"
    end

    # The requested order has to account for every photo in the directory,
    # exactly once, or renumbering would lose one.
    def permutation!(gallery, names)
      names = Array(names).map { |name| repo.photo_name!(name) }
      on_disk = repo.photos_on_disk(gallery)
      return names if names.sort == on_disk.sort && names.uniq.length == names.length

      raise InvalidRequest,
            "the order must list each of the #{on_disk.length} photos in #{gallery.title} once"
    end

    # Renames photos and their thumbnails so that `ordered` becomes 01.jpg
    # onwards. Two passes via temporary names, because renaming straight to the
    # target would overwrite a file that has not been moved yet. Returns the
    # old name to new name mapping for the files that actually moved.
    def renumber(gallery, ordered)
      targets = ordered.each_with_index.to_h { |name, index| [name, format("%02d.jpg", index + 1)] }
      moved = targets.reject { |old, new| old == new }
      return {} if moved.empty?

      staged = moved.keys.to_h { |old| [old, "moving-#{SecureRandom.hex(4)}-#{old}"] }
      staged.each { |old, temporary| rename_files(gallery, old, temporary) }
      staged.each { |old, temporary| rename_files(gallery, temporary, moved.fetch(old)) }

      gallery.rewrite_captions(ordered.map { targets.fetch(_1) }, renames: targets)
      moved
    end

    def rename_files(gallery, from, to)
      [[repo.image_dir(gallery), from, to], [repo.thumb_dir(gallery), from, to]].each do |dir, a, b|
        source = dir.join(a)
        FileUtils.mv(source, dir.join(b)) if source.exist?
      end
    end

    def remove_files(gallery, name)
      [repo.image_path(gallery, name), repo.thumb_path(gallery, name)].each do |path|
        FileUtils.rm_f(path)
      end
    end

    # Copies a photo (and its thumbnail) into another gallery under the next
    # free number. The source is only removed once this has succeeded.
    def copy_into(source, destination, name)
      new_name = next_free_name(destination)
      FileUtils.mkdir_p(repo.image_dir(destination))
      FileUtils.mkdir_p(repo.thumb_dir(destination))
      FileUtils.cp(repo.image_path(source, name), repo.image_dir(destination).join(new_name))

      thumb = repo.thumb_path(source, name)
      FileUtils.cp(thumb, repo.thumb_dir(destination).join(new_name)) if thumb.exist?
      new_name
    end

    # The lowest free slot, matching what optimize-images does.
    def next_free_name(gallery)
      taken = repo.photos_on_disk(gallery)
      (1..99).each do |n|
        name = format("%02d.jpg", n)
        return name unless taken.include?(name)
      end
      raise InvalidRequest, "#{gallery.title} is full"
    end

    def after_last_in_section(document, section)
      last = document.galleries.rindex { _1.section == section }
      last ? last + 1 : nil
    end

    def identifier!(id)
      id = id.to_s
      return id if id.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)

      raise InvalidRequest, "#{id.inspect} is not a usable gallery id"
    end

    def jpeg!(source)
      path = Pathname(source)
      raise InvalidRequest, "#{path.basename} is not a file" unless path.file?
      raise InvalidRequest, "#{path.basename} is empty" if path.size.zero?
      raise InvalidRequest, "#{path.basename} is too large" if path.size > MAX_UPLOAD_BYTES

      signature = File.binread(path, 3)
      return path if signature == JPEG_SIGNATURE

      raise InvalidRequest, "#{path.basename} is not a JPEG"
    end
  end
end
