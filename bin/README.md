# Managing photos

Two scripts drive the photography section. The site reads galleries straight
from [`_data/galleries.yml`](../_data/galleries.yml) and enumerates the JPEGs on
disk, so you never touch layouts or CSS to add or remove images.

- `optimize-images` — resize/recompress JPEGs, build thumbnails, add a photo to
  a gallery. **macOS only** (uses `sips`).
- `generate-photo-pages` — create/remove the per-photo page stubs so each photo
  gets its own URL. Safe to re-run.

Run both from the repo root.

## Add a photo to an existing gallery

```bash
bin/optimize-images add ~/path/to/new.jpg assets/ph/mf/misc/
```

This copies the file in as the next free `NN.jpg`, resizes it (1600px long edge,
quality 80), builds the grid thumbnail under `assets/thumbs/`, and prints a
caption line to paste. Then:

1. Paste the caption into that gallery's `captions:` block in
   `_data/galleries.yml`:

   ```yaml
   "20.jpg": "Subject [Camera, Lens - Film]"
   ```

   The `[Camera, Lens - Film]` part is optional. It auto-splits into the small
   uppercase gear line shown under the photo (commas and ` - ` become ` · `).
   Leaving the whole value empty (`"20.jpg": ""`) is fine for no caption.

2. Generate its page:

   ```bash
   bin/generate-photo-pages
   ```

The hub grid, gallery grid, thumbnail, and prev/next links all update
themselves from the folder contents plus that YAML.

## Remove a photo

Delete the image and its thumbnail, then regenerate:

```bash
rm assets/ph/mf/misc/20.jpg assets/thumbs/ph/mf/misc/20.jpg
bin/generate-photo-pages   # removes the orphaned page automatically
```

Also delete that photo's `"20.jpg":` line from the gallery's `captions:` block.

## Add a whole new gallery

1. Add a block to `_data/galleries.yml` (order in the file is the display order
   and drives the gallery-to-gallery prev/next chain):

   ```yaml
   - id: mf-street            # unique slug
     url: /ph/mf/street.html  # page URL
     title: Street            # shown as the heading and hub tile label
     section: Medium format   # groups it under this hub section
     dir: /assets/ph/mf/street/
     cover: "01.jpg"          # which photo becomes the hub tile
     captions:
       "01.jpg": "Subject [Camera, Lens - Film]"
   ```

2. Put the JPEGs in that `dir`, then:

   ```bash
   bin/optimize-images assets/ph/mf/street   # optimize the batch in place
   bin/optimize-images thumbs                # build any missing thumbnails
   bin/generate-photo-pages
   ```

The gallery appears on the hub under its `section` automatically.

## Ordering

- **Photos within a gallery**: filename order (`01.jpg`, `02.jpg`, …). Renumber
  files to reorder; this also sets the in-gallery prev/next order.
- **Galleries and sections**: top-to-bottom order in `_data/galleries.yml`.

## Other commands

```bash
bin/optimize-images <file-or-dir> ...   # recompress in place (re-runnable no-op
                                        # once files are already optimized)
bin/optimize-images thumbs [<dir>]      # build missing thumbnails (default: assets/ph)
bin/optimize-images --help              # full usage
```

## Notes

- Both scripts are excluded from the Jekyll build (see `exclude:` in
  `_config.yml`), so this README is not published.
- After any change, preview locally with `bundle exec jekyll serve` before
  committing.
