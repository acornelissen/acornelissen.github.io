// The manager talks to the local server, which owns the files. Nothing here
// decides anything on its own: every change is sent, applied on disk, and the
// answer is the state read back. What you see is what is in the repo.

const TOKEN = document.querySelector('meta[name="gallery-token"]').content;
const STILL = window.matchMedia('(prefers-reduced-motion: reduce)');

const el = (id) => document.getElementById(id);
const sheet = el('sheet');
const rail = el('rail');
const status = el('status');
const curtain = el('curtain');

let state = { sections: [], galleries: [] };
let problems = [];
let currentId = localStorage.getItem('gallery') || null;
// Names whose file the last change renamed, flashed once on the sheet.
let renamed = [];
// A drag ends in a click. This keeps that click from also doing something.
let dragJustEnded = false;

const current = () => state.galleries.find((g) => g.id === currentId) || state.galleries[0];
const frameName = (index) => `${String(index + 1).padStart(2, '0')}.jpg`;
const galleryById = (id) => state.galleries.find((g) => g.id === id);

// --- talking to the server ---------------------------------------------

// Runs a change and reports it. A failed change says why and puts the screen
// back to what is actually on disk, so the two never drift apart.
function change(path, payload, describe) {
  return send(path, payload).then(
    () => { if (describe) say(describe()); },
    () => {}
  );
}

function send(path, payload) {
  return request(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Gallery-Token': TOKEN },
    body: JSON.stringify(payload),
  });
}

function upload(galleryId, files) {
  const form = new FormData();
  form.append('gallery', galleryId);
  for (const file of files) form.append('files[]', file, file.name);
  return request('/api/photos/add', {
    method: 'POST',
    headers: { 'X-Gallery-Token': TOKEN },
    body: form,
  });
}

async function request(path, options) {
  curtain.hidden = false;
  try {
    const response = await fetch(path, options);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || `the server answered ${response.status}`);
    state = data.state;
    problems = data.problems;
    return data;
  } catch (error) {
    renamed = [];
    say(error.message, 'bad');
    await load({ quiet: true }).catch(() => {});
    throw error;
  } finally {
    curtain.hidden = true;
    render();
  }
}

async function load({ quiet = false } = {}) {
  const response = await fetch('/api/state');
  const data = await response.json();
  state = data.state;
  problems = data.problems;
  if (!quiet) render();
}

function say(message, tone) {
  status.textContent = message;
  if (tone) status.dataset.tone = tone;
  else delete status.dataset.tone;
}

// --- drawing ------------------------------------------------------------

function render() {
  if (!state.galleries.length) return;
  if (!galleryById(currentId)) currentId = state.galleries[0].id;
  localStorage.setItem('gallery', currentId);
  drawRail();
  drawSectionNames();
  drawStage();
  drawSheet();
  drawHealth();
}

// One flat list, headings included, so a gallery can be dragged from one
// section into another and land under the right heading.
function drawRail() {
  const items = [];
  for (const section of state.sections) {
    const heading = document.createElement('li');
    heading.className = 'rail__section';
    heading.dataset.section = section.name;
    heading.textContent = section.name;
    items.push(heading);

    for (const id of section.gallery_ids) {
      const gallery = galleryById(id);
      const item = document.createElement('li');
      const button = document.createElement('button');
      button.className = 'rail__item';
      button.type = 'button';
      button.dataset.gallery = id;
      button.setAttribute('aria-current', String(id === currentId));

      const name = document.createElement('span');
      name.className = 'rail__name';
      name.textContent = gallery.title;

      const count = document.createElement('span');
      count.className = 'rail__count';
      count.textContent = gallery.photos.length;

      button.append(name, count);
      item.append(button);
      items.push(item);
    }
  }
  rail.replaceChildren(...items);
}

function drawSectionNames() {
  const names = [...new Set(state.galleries.map((g) => g.section))];
  el('sections').replaceChildren(
    ...names.map((name) => {
      const option = document.createElement('option');
      option.value = name;
      return option;
    })
  );
}

function drawStage() {
  const gallery = current();
  el('gallery-title').value = gallery.title;
  el('gallery-section').value = gallery.section;
  el('photo-count').textContent =
    gallery.photos.length === 1 ? '1 photo' : `${gallery.photos.length} photos`;
  el('site-link').href = gallery.url;
  el('delete-gallery').disabled = gallery.photos.length > 0;
  el('delete-gallery').title = gallery.photos.length
    ? 'Move or delete its photos first'
    : 'Remove this gallery';
  el('empty').hidden = gallery.photos.length > 0;
}

function drawSheet() {
  const gallery = current();
  sheet.replaceChildren(...gallery.photos.map((photo, index) => cell(gallery, photo, index)));
  if (renamed.length) flashRenames();
}

function cell(gallery, photo, index) {
  const item = document.createElement('li');
  item.className = 'cell';
  item.dataset.photo = photo.name;
  item.dataset.cover = String(gallery.cover === photo.name);

  const frame = document.createElement('div');
  frame.className = 'frame';
  frame.tabIndex = 0;
  frame.setAttribute(
    'aria-label',
    `${photo.name}, position ${index + 1} of ${gallery.photos.length}` +
      (photo.caption ? `. ${photo.caption}` : '') +
      '. Hold Control and press an arrow key to move it.'
  );

  const image = document.createElement('img');
  image.src = photo.thumb;
  image.alt = photo.caption || photo.name;
  image.draggable = false;
  // A thumbnail can be missing; the photo itself still shows what it is.
  image.addEventListener('error', () => { image.src = photo.image; }, { once: true });

  const number = document.createElement('span');
  number.className = 'frame__number';
  number.textContent = photo.name.replace('.jpg', '');

  frame.append(image, number);

  const caption = document.createElement('input');
  caption.className = 'caption';
  caption.value = photo.caption;
  caption.placeholder = 'Caption [Camera, Lens - Film]';
  caption.setAttribute('aria-label', `Caption for ${photo.name}`);
  caption.addEventListener('change', () =>
    change(
      '/api/photos/caption',
      { gallery: gallery.id, photo: photo.name, caption: caption.value },
      () => `Caption saved for ${photo.name}.`
    )
  );

  const actions = document.createElement('div');
  actions.className = 'cell__actions';
  actions.append(
    action('Cover', 'cover', gallery.cover === photo.name, () =>
      change(
        '/api/photos/cover',
        { gallery: gallery.id, photo: photo.name },
        () => `${photo.name} is the cover for ${gallery.title}.`
      )
    ),
    action('Delete', 'delete', null, () => {
      if (!confirm(`Delete ${photo.name} from ${gallery.title}? The file goes too.`)) return;
      const shifting = gallery.photos.length - index - 1;
      renamed = gallery.photos.slice(index + 1).map((_, offset) => frameName(index + offset));
      change('/api/photos/delete', { gallery: gallery.id, photo: photo.name }, () =>
        shifting
          ? `Deleted ${photo.name}. ${shifting} later ${
              shifting === 1 ? 'photo' : 'photos'
            } moved up a number.`
          : `Deleted ${photo.name}.`
      );
    })
  );

  item.append(frame, caption, actions);
  return item;
}

function action(label, kind, pressed, run) {
  const button = document.createElement('button');
  button.className = 'cell__action';
  button.type = 'button';
  button.dataset.act = kind;
  button.textContent = label;
  if (pressed !== null) button.setAttribute('aria-pressed', String(pressed));
  button.addEventListener('click', run);
  return button;
}

// Renaming files is the part of a reorder you cannot see in a photo grid, so
// the numbers that changed say so on their way past.
function flashRenames() {
  const marks = renamed
    .map((name) => sheet.querySelector(`[data-photo="${name}"] .frame__number`))
    .filter(Boolean);
  renamed = [];
  for (const mark of marks) mark.classList.add('is-renamed');
  setTimeout(() => marks.forEach((mark) => mark.classList.remove('is-renamed')), 1100);
}

function drawHealth() {
  const toggle = el('health-toggle');
  const panel = el('health');
  toggle.hidden = problems.length === 0;
  toggle.textContent = `${problems.length} out of step`;
  if (!problems.length) {
    panel.hidden = true;
    toggle.setAttribute('aria-expanded', 'false');
    return;
  }
  el('health-list').replaceChildren(
    ...problems.map((problem) => {
      const item = document.createElement('li');
      const gallery = galleryById(problem.gallery);
      const name = document.createElement('b');
      name.textContent = gallery ? gallery.title : problem.gallery;
      item.append(name, document.createTextNode(problem.detail));
      return item;
    })
  );
}

// --- moving photos ------------------------------------------------------

const orderNow = () => [...sheet.children].map((cell) => cell.dataset.photo);

// Which files a reorder will rename, and so which photo URLs on the site are
// about to change.
const renamesFor = (order) =>
  order.map((_, index) => frameName(index)).filter((name, index) => order[index] !== name);

function applyOrder(order, announce) {
  const gallery = current();
  const changed = renamesFor(order);
  if (!changed.length) return Promise.resolve();

  renamed = changed;
  const count = changed.length;
  return change('/api/photos/reorder', { gallery: gallery.id, names: order }, () =>
    `${announce ? `${announce} ` : ''}Renamed ${count} ${count === 1 ? 'file' : 'files'} on disk.`
  );
}

// FLIP: measure, move, then play the difference back so the photos slide into
// place rather than jumping.
function slide(container, mutate) {
  if (STILL.matches) return mutate();
  const before = new Map(
    [...container.children].map((child) => [child, child.getBoundingClientRect()])
  );
  mutate();
  for (const child of container.children) {
    const was = before.get(child);
    if (!was) continue;
    const now = child.getBoundingClientRect();
    const dx = was.left - now.left;
    const dy = was.top - now.top;
    if (!dx && !dy) continue;
    child.style.transition = 'none';
    child.style.transform = `translate(${dx}px, ${dy}px)`;
    requestAnimationFrame(() => {
      child.style.transition = '';
      child.style.transform = '';
    });
  }
}

function dropTarget(x, y, items, held) {
  for (const item of items) {
    if (item === held) continue;
    const box = item.getBoundingClientRect();
    if (x >= box.left && x <= box.right && y >= box.top && y <= box.bottom) {
      return { item, after: x > box.left + box.width / 2 };
    }
  }
  return null;
}

// One drag implementation, used for photos on the sheet and galleries in the
// rail. Pointer events, so trackpad, mouse and touch all behave the same.
function draggable({ container, handle, onDrop, onOver }) {
  container.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    const grip = event.target.closest(handle);
    if (!grip) return;
    const held = grip.closest('li');
    if (!held) return;

    const start = { x: event.clientX, y: event.clientY };
    const box = grip.getBoundingClientRect();
    let flying = null;
    let hovered = null;

    const move = (moveEvent) => {
      const dx = moveEvent.clientX - start.x;
      const dy = moveEvent.clientY - start.y;
      if (!flying && Math.hypot(dx, dy) < 5) return;

      if (!flying) {
        grip.setPointerCapture(moveEvent.pointerId);
        flying = grip.cloneNode(true);
        flying.classList.add('is-flying');
        Object.assign(flying.style, {
          left: `${box.left}px`,
          top: `${box.top}px`,
          width: `${box.width}px`,
          height: `${box.height}px`,
        });
        document.body.append(flying);
        held.classList.add('is-lifted');
      }

      flying.style.transform = `translate(${dx}px, ${dy}px) rotate(-1.2deg)`;

      if (onOver) hovered = onOver(moveEvent.clientX, moveEvent.clientY, hovered);
      if (hovered) return;

      const target = dropTarget(moveEvent.clientX, moveEvent.clientY, container.children, held);
      if (!target) return;
      slide(container, () =>
        target.item.insertAdjacentElement(target.after ? 'afterend' : 'beforebegin', held)
      );
    };

    const end = () => {
      container.removeEventListener('pointermove', move);
      container.removeEventListener('pointerup', end);
      container.removeEventListener('pointercancel', end);
      if (!flying) return;
      flying.remove();
      held.classList.remove('is-lifted');
      if (onOver) onOver(-1, -1, hovered);
      dragJustEnded = true;
      setTimeout(() => { dragJustEnded = false; }, 0);
      onDrop(held, hovered);
    };

    container.addEventListener('pointermove', move);
    container.addEventListener('pointerup', end);
    container.addEventListener('pointercancel', end);
  });
}

// Dragging a photo onto a gallery in the rail moves it there.
function railTargetAt(x, y, previous) {
  const found = [...rail.querySelectorAll('.rail__item')].find((item) => {
    if (item.dataset.gallery === currentId) return false;
    const box = item.getBoundingClientRect();
    return x >= box.left && x <= box.right && y >= box.top && y <= box.bottom;
  });
  if (previous && previous !== found) previous.classList.remove('is-target');
  if (found) found.classList.add('is-target');
  return found || null;
}

draggable({
  container: sheet,
  handle: '.frame',
  onOver: railTargetAt,
  onDrop: (held, target) => {
    const gallery = current();
    const photo = held.dataset.photo;
    if (target) {
      const destination = target.dataset.gallery;
      const name = galleryById(destination).title;
      change('/api/photos/move', { from: gallery.id, to: destination, photo }, () =>
        `Moved ${photo} to ${name}.`
      );
      return;
    }
    applyOrder(orderNow());
  },
});

// Reading the rail back gives both the new gallery order and, from the heading
// each one now sits under, which section it belongs to.
function railLayout() {
  const order = [];
  const sections = {};
  let section = null;
  for (const item of rail.children) {
    if (item.classList.contains('rail__section')) {
      section = item.dataset.section;
      continue;
    }
    const id = item.querySelector('.rail__item').dataset.gallery;
    order.push(id);
    sections[id] = section ?? galleryById(id).section;
  }
  return { order, sections };
}

draggable({
  container: rail,
  handle: '.rail__item',
  onDrop: async (held) => {
    const id = held.querySelector('.rail__item').dataset.gallery;
    const { order, sections } = railLayout();
    const moved = sections[id] !== galleryById(id).section;
    try {
      if (moved) await send('/api/galleries/update', { gallery: id, section: sections[id] });
      await send('/api/galleries/reorder', { ids: order });
      say(moved ? `Moved to ${sections[id]}.` : 'Gallery order saved.');
    } catch {
      // request() has already explained it and redrawn from disk.
    }
  },
});

// The keyboard does the same move, without a mouse.
sheet.addEventListener('keydown', (event) => {
  const frame = event.target.closest('.frame');
  if (!frame || !(event.ctrlKey || event.metaKey)) return;
  const step = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -columns(), ArrowDown: columns() }[
    event.key
  ];
  if (!step) return;
  event.preventDefault();

  const order = orderNow();
  const from = order.indexOf(frame.closest('.cell').dataset.photo);
  const to = Math.min(order.length - 1, Math.max(0, from + step));
  if (to === from) return;

  order.splice(to, 0, ...order.splice(from, 1));
  applyOrder(order, `Moved to position ${to + 1} of ${order.length}.`).then(() =>
    sheet.children[to]?.querySelector('.frame').focus()
  );
});

const columns = () => getComputedStyle(sheet).gridTemplateColumns.split(' ').length || 1;

rail.addEventListener('click', (event) => {
  const item = event.target.closest('.rail__item');
  if (!item || dragJustEnded) return;
  currentId = item.dataset.gallery;
  say('');
  render();
});

// --- adding photos ------------------------------------------------------

function addFiles(files) {
  const jpegs = [...files].filter((file) => /\.jpe?g$/i.test(file.name));
  if (!jpegs.length) {
    say('Galleries take JPEGs only.', 'bad');
    return;
  }
  const gallery = current();
  upload(gallery.id, jpegs).then(
    () =>
      say(
        `Added ${jpegs.length} ${jpegs.length === 1 ? 'photo' : 'photos'} to ${
          gallery.title
        }. The captions are yours to write.`
      ),
    () => {}
  );
}

for (const type of ['dragenter', 'dragover']) {
  sheet.addEventListener(type, (event) => {
    if (![...event.dataTransfer.types].includes('Files')) return;
    event.preventDefault();
    sheet.classList.add('is-receiving');
  });
}

sheet.addEventListener('dragleave', (event) => {
  if (sheet.contains(event.relatedTarget)) return;
  sheet.classList.remove('is-receiving');
});

sheet.addEventListener('drop', (event) => {
  sheet.classList.remove('is-receiving');
  if (!event.dataTransfer.files.length) return;
  event.preventDefault();
  addFiles(event.dataTransfer.files);
});

el('add-photos').addEventListener('click', () => el('file-input').click());
el('file-input').addEventListener('change', (event) => {
  if (event.target.files.length) addFiles(event.target.files);
  event.target.value = '';
});

// --- gallery details ----------------------------------------------------

el('gallery-title').addEventListener('change', (event) =>
  change('/api/galleries/update', { gallery: currentId, title: event.target.value }, () =>
    'Title saved.'
  )
);

el('gallery-section').addEventListener('change', (event) =>
  change('/api/galleries/update', { gallery: currentId, section: event.target.value }, () =>
    'Section saved.'
  )
);

el('delete-gallery').addEventListener('click', () => {
  const gallery = current();
  if (!confirm(`Delete ${gallery.title}? Its folder goes with it.`)) return;
  change('/api/galleries/delete', { gallery: gallery.id }, () => `Deleted ${gallery.title}.`);
});

const form = el('new-gallery-form');
const newButton = el('new-gallery');
// Named lookup: a form's own properties shadow controls called title or section.
const field = (name) => form.elements.namedItem(name);

newButton.addEventListener('click', () => {
  const opening = form.hidden;
  form.hidden = !opening;
  newButton.setAttribute('aria-expanded', String(opening));
  if (opening) field('title').focus();
});

form.querySelector('[data-cancel]').addEventListener('click', () => {
  form.hidden = true;
  newButton.setAttribute('aria-expanded', 'false');
  newButton.focus();
});

field('slug').addEventListener('input', () => {
  const slug = field('slug').value.trim();
  el('new-gallery-preview').textContent = slug ? `/ph/${slug}.html — assets/ph/${slug}/` : '';
});

form.addEventListener('submit', (event) => {
  event.preventDefault();
  const slug = field('slug').value.trim();
  const id = slug.replace(/\//g, '-');
  send('/api/galleries/create', {
    id,
    title: field('title').value.trim(),
    section: field('section').value.trim(),
    slug,
  }).then(
    () => {
      currentId = id;
      form.reset();
      form.hidden = true;
      newButton.setAttribute('aria-expanded', 'false');
      el('new-gallery-preview').textContent = '';
      render();
      say('Gallery created. Drop some photos in.');
    },
    () => {}
  );
});

// --- health -------------------------------------------------------------

el('health-toggle').addEventListener('click', (event) => {
  const showing = el('health').hidden;
  el('health').hidden = !showing;
  event.currentTarget.setAttribute('aria-expanded', String(showing));
});

el('repair').addEventListener('click', () =>
  send('/api/repair', {}).then(
    () =>
      say(
        problems.length
          ? 'Fixed what could be fixed. What is left needs a decision from you.'
          : 'Everything is back in step.'
      ),
    () => {}
  )
);

load().catch(() => say('The server is not answering. Is it still running?', 'bad'));
