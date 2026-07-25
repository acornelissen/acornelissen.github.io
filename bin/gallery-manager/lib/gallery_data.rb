require "date"
require "yaml"

module GalleryManager
  # One gallery as described by _data/galleries.yml. Captions are an ordered
  # map of filename to caption text, and their order is only ever a mirror of
  # the filenames on disk -- the site itself takes display order from the
  # filenames, not from this file.
  class Gallery
    attr_accessor :id, :url, :title, :section, :dir, :cover, :captions
    # Whether this gallery was separated from the one above it by a blank line.
    # Cosmetic, but preserving it keeps diffs to the lines that actually changed.
    attr_accessor :blank_before

    def initialize(id:, url:, title:, section:, dir:, cover: nil, captions: {}, blank_before: false)
      @id = id
      @url = url
      @title = title
      @section = section
      @dir = dir
      @cover = cover
      @captions = captions
      @blank_before = blank_before
    end

    def photo_names = captions.keys

    def caption(name) = captions[name].to_s

    # Rewrites the caption map so its keys are `names`, in that order, carrying
    # each caption across from the name the photo had before.
    def rewrite_captions(names, renames: {})
      previous = captions
      @captions = names.to_h do |name|
        old_name = renames.key(name) || name
        [name, previous.fetch(old_name, "")]
      end
    end

    def to_h
      { "id" => id, "url" => url, "title" => title, "section" => section,
        "dir" => dir, "cover" => cover, "captions" => captions }
    end
  end

  # The whole of galleries.yml: its header comment, its galleries, and the
  # blank lines between them. Parses with Psych for the data and re-reads the
  # raw text for the layout, then writes the file back in the same style.
  class GalleryDocument
    GALLERY_START = /^- id:/.freeze

    attr_reader :galleries, :header

    def initialize(galleries:, header: "")
      @galleries = galleries
      @header = header
    end

    def self.load_file(path) = parse(File.read(path))

    def self.parse(text)
      # A title like 2024-01-05 parses as a date unless dates are allowed
      # through; the writer turns it back into quoted text on the way out.
      records = YAML.safe_load(text, permitted_classes: [Date], aliases: false) || []
      blanks = blank_line_flags(text)

      galleries = records.each_with_index.map do |record, index|
        Gallery.new(
          id: record["id"], url: record["url"], title: record["title"],
          section: record["section"], dir: record["dir"], cover: record["cover"],
          captions: record["captions"] || {},
          blank_before: index.positive? && blanks.fetch(record["id"], false)
        )
      end

      new(galleries: galleries, header: header_of(text))
    end

    # Everything before the first gallery, kept verbatim.
    def self.header_of(text)
      lines = text.lines
      first = lines.index { |line| line.match?(GALLERY_START) }
      first ? lines[0...first].join : text
    end

    # Which galleries had a blank line immediately above them.
    def self.blank_line_flags(text)
      flags = {}
      previous = nil
      text.lines.each do |line|
        flags[Regexp.last_match(1)] = previous&.strip&.empty? || false if line =~ /^- id:\s*(\S+)/
        previous = line
      end
      flags
    end
    private_class_method :header_of, :blank_line_flags

    def gallery(id) = galleries.find { _1.id == id }

    def gallery!(id)
      gallery(id) or raise ArgumentError, "no gallery with id #{id.inspect}"
    end

    def sections = galleries.map(&:section).uniq

    def add(gallery, index: nil)
      gallery.blank_before = galleries.empty? ? false : galleries.last.section != gallery.section
      index ? galleries.insert(index, gallery) : galleries.push(gallery)
      gallery
    end

    def remove(id)
      removed = gallery!(id)
      galleries.delete(removed)
      removed
    end

    def write(path) = File.write(path, to_yaml)

    def to_yaml
      body = galleries.each_with_index.map do |gallery, index|
        (index.positive? && gallery.blank_before ? "\n" : "") + gallery_to_yaml(gallery)
      end
      header + body.join
    end

    private

    def gallery_to_yaml(gallery)
      lines = +""
      lines << "- id: #{scalar(gallery.id)}\n"
      lines << "  url: #{scalar(gallery.url)}\n"
      lines << "  title: #{scalar(gallery.title)}\n"
      lines << "  section: #{scalar(gallery.section)}\n"
      lines << "  dir: #{scalar(gallery.dir)}\n"
      lines << "  cover: #{quote(gallery.cover)}\n" if gallery.cover
      return lines << "  captions: {}\n" if gallery.captions.empty?

      lines << "  captions:\n"
      gallery.captions.each { |name, caption| lines << "    #{quote(name)}: #{quote(caption)}\n" }
      lines
    end

    # Plain where the file already writes things plain, quoted where a plain
    # scalar would not read back as the same string.
    def scalar(value)
      plain?(value) ? value : quote(value)
    end

    def quote(value)
      escaped = value.to_s
                     .gsub("\\", "\\\\\\\\")
                     .gsub('"', '\"')
                     .gsub("\n", '\n')
                     .gsub("\t", '\t')
      %("#{escaped}")
    end

    def plain?(value)
      return false unless value.is_a?(String)
      return false if value.empty? || value != value.strip
      return false if value.match?(/\A[-?:,\[\]{}#&*!|>'"%@`]/)
      return false if value.match?(/:\s|\s#/)

      YAML.safe_load(value) == value
    rescue Psych::Exception
      false
    end
  end
end
