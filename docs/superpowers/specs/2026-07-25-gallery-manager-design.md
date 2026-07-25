# Gallery manager

A local web tool for managing the photography section: reorder photos by
dragging them, drop in new ones, edit captions, pick covers, and manage whole
galleries. Replaces the hand-run script sequence documented in
[`bin/README.md`](../../../bin/README.md).

## Why

Everything the site needs already lives in `_data/galleries.yml` plus the JPEGs
on disk, and two scripts do the mechanical work. What is missing is a way to see
the photos while editing them. Reordering is the worst of it: order is filename
order, so moving a photo means renaming a run of files, their thumbnails and
their generated page stubs, then rewriting the caption keys to match. Nobody
does that by hand for fun.

## Scope

In scope: reorder photos within a gallery, add photos, edit captions, set the
cover, delete photos, move a photo between galleries, and create, rename,
reorder and delete galleries.

Out of scope: editing writing posts, image adjustment, anything that touches
`assets/wr`, and deploying. The tool never commits; git stays the undo button.

## Decisions

**Order stays filename order.** `01.jpg`…`NN.jpg` is the display order, as
today. A drag renames files. The alternative — an explicit order list in YAML —
would keep photo URLs stable and make diffs smaller, but it changes the site's
data model, both gallery templates, the page generator and the README. Rejected:
the point of the tool is to absorb the mechanical pain, not to redesign the
site around it. Consequence to accept: reordering changes the URL of every photo
after the insertion point.

**Changes apply immediately.** No staging, no save button. Each action writes to
the working tree and the UI re-reads the result. Git is the undo.

**Ruby and Sinatra.** The repo already pins Ruby 3.3 and `generate-photo-pages`
is Ruby. Sinatra and puma go in a `:development` group of the `Gemfile`; the
GitHub Pages build supplies its own gems and ignores ours, so the published site
is unaffected. The frontend is one HTML, one CSS and one JS file — no bundler,
no npm.

**The existing scripts stay the single source of truth** for resizing,
thumbnailing, dimension recording and stub generation. The server shells out to
them rather than reimplementing `sips` handling.

## Layout

The tool lives in `bin/gallery-manager/`, which `_config.yml` already excludes
from the Jekyll build.

| File | Responsibility |
| --- | --- |
| `server.rb` | Sinatra app: HTTP, request guards, JSON in and out |
| `lib/repo.rb` | Paths within the repo, and validation of anything client-supplied |
| `lib/gallery_data.rb` | Parse `galleries.yml` into gallery objects; write it back |
| `lib/yaml_writer.rb` | Emit `galleries.yml` in its existing hand-written style |
| `lib/gallery_store.rb` | The operations, and the only code that mutates disk |
| `lib/scripts.rb` | Invokes `optimize-images` and `generate-photo-pages` |
| `lib/health.rb` | Detects drift between YAML, images, thumbs, dims and stubs |
| `public/` | `index.html`, `app.css`, `app.js` |

`gallery_store.rb` depends on `scripts.rb` through constructor injection so tests
can pass a recording double and never invoke `sips`.

## Operations

Each one runs to completion on disk before the response returns, and the
response carries fresh state read back from disk.

**Reorder** — given a gallery id and the filenames in their new order, verify the
list is a permutation of what is on disk, then rename in two phases: every
affected image, thumbnail and page stub moves to a temporary name, then to its
final `NN.jpg`. Two phases because a direct rename would clobber a file that has
not moved yet. Captions are rewritten in the new key order. Then
`generate-photo-pages` and `optimize-images dims` run.

**Add** — uploaded files are written to a temporary directory outside the repo,
checked for a JPEG signature, then passed to `optimize-images add`, which
assigns the next free number, resizes and thumbnails. Captions start empty.
`generate-photo-pages` and `dims` run once for the whole batch, not per file.

**Delete** — remove the image, its thumbnail, its stub and its caption entry,
then renumber the remainder to close the gap. If the deleted photo was the
cover, the first remaining photo takes over.

**Move** — a delete from the source gallery and an add to the destination, with
the caption carried across. The file is copied before it is removed, so a
failure mid-way leaves the photo in the source gallery rather than nowhere.

**Caption and cover** — a YAML write. No scripts needed.

**Gallery create, rename, reorder, delete** — YAML writes plus directory
creation or removal. Deleting a gallery requires it to be empty, so photos are
never destroyed as a side effect of a mis-click.

## The YAML writer

`galleries.yml` is hand-written: a three-line header comment, a blank line
between sections, filename keys quoted, captions quoted. Psych's dumper would
throw all of that away and produce a diff touching every line. So the writer
emits the file itself from the parsed structure, preserving the header and the
blank-line grouping, and quoting values the way the file already does. Its test
asserts that parsing the current file and writing it straight back produces a
byte-identical result.

## Frontend

A sidebar lists sections and their galleries; the main panel shows the selected
gallery's photos as a grid of square thumbnails with the caption editable
underneath each. Dragging within the grid reorders. Dragging a tile onto a
gallery in the sidebar moves it there. Dragging galleries in the sidebar
reorders them. Dropping files from Finder anywhere on the grid adds them.

Tiles move optimistically on drop and the grid re-renders from the server's
response, so what is on screen is what is on disk.

Tile sorting is pointer events, written for this tool — small enough not to
warrant a dependency. File drops use the native HTML5 drop event, which is the
only way to receive files from Finder.

## Accessibility

Drag is never the only way to do something. Photo tiles and sidebar galleries
are focusable; `Ctrl`/`Cmd` with an arrow key moves the focused item, and an
`aria-live` region announces the result ("moved to position 4 of 19"). Deleting,
setting a cover and editing a caption are ordinary buttons and text fields. The
drop zone has a matching file input. Focus stays visible throughout, and the
palette follows the site's monochrome contrast.

## Security

The server binds to `127.0.0.1` only. A browser tab on any site can still reach
a local port, so every mutating request must carry a token generated at boot and
embedded in the page, and must present a same-origin `Origin` header.

Nothing client-supplied reaches the filesystem as a path. Galleries are
addressed by their `id` in `galleries.yml`; photos by a basename that must match
`\A\d{2}\.jpg\z` and must already exist in that gallery's directory. Uploads are
capped in size, must carry a JPEG signature, and are staged outside the repo.
Subprocesses are invoked with argument arrays, never an interpolated shell
string.

## Errors

An operation either completes or reports why it did not. Failures return a
message, the UI shows it and refetches state rather than assuming what happened.
Pre-flight checks refuse work that would corrupt a gallery — a reorder list that
is not a permutation of the directory, a gallery whose files are not
sequentially numbered, a duplicate gallery id.

The health panel reports drift found at load: photos with no caption entry,
caption entries with no photo, missing thumbnails, missing dimensions, orphaned
stubs, and covers pointing at absent files. A fix button runs the scripts that
resolve the fixable ones.

## Testing

Minitest, test-first, against a temporary fixture repo built per test: a small
`galleries.yml`, a few zero-byte JPEGs, matching thumbs and stubs. Because
`scripts.rb` is injected, no test needs `sips` or the real binaries.

Covered: the YAML writer's round-trip fidelity and its output for each edit;
reorder as a permutation, including the two-phase rename and caption reordering;
delete with renumbering and cover reassignment; move between galleries; add;
gallery CRUD; every validation rule, including rejected path traversal and
malformed filenames; and health detection for each drift type.

The drag interactions are checked by hand — no browser automation for a tool
with one user.

## Running it

```sh
mise run galleries   # boots the server and opens the browser
mise run test        # runs the suite
```
