require "open3"

module GalleryManager
  # The two scripts in bin/ stay the source of truth for resizing,
  # thumbnailing, recording dimensions and generating photo pages. This is the
  # only place that runs them, so tests can substitute the parts that need
  # sips while leaving the rest real.
  class Scripts
    attr_reader :repo

    def initialize(repo)
      @repo = repo
    end

    # Copies a photo into a gallery as the next free NN.jpg and thumbnails it.
    # Returns the name the script chose, read back from its own output rather
    # than guessed.
    def add_photo(source, gallery_dir)
      output = run("bin/optimize-images", "add", source.to_s, gallery_dir.to_s)
      name = output[%r{^Added .*/(\d{2}\.jpg)\s*$}, 1]
      raise Error, "optimize-images did not report a filename:\n#{output}" unless name

      name
    end

    def generate_photo_pages = run("bin/generate-photo-pages")

    # No arguments on purpose: dims rewrites the whole file, so narrowing the
    # roots here would drop the article images from it.
    def record_dimensions = run("bin/optimize-images", "dims")

    def build_thumbs = run("bin/optimize-images", "thumbs")

    private

    # Argument arrays only. Nothing here is ever handed to a shell.
    def run(*argv)
      output, errors, status = Open3.capture3(*argv, chdir: repo.root.to_s)
      return output if status.success?

      detail = errors.strip.empty? ? output.strip : errors.strip
      raise Error, "#{argv.first} failed: #{detail}"
    end
  end
end
