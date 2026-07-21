// Minimal lightbox for gallery pages. No dependencies.
// Click a grid item to open; arrows or left/right keys to move; Esc,
// the close button, or a click on the backdrop to close.
(function () {
  "use strict";

  var links = Array.prototype.slice.call(
    document.querySelectorAll(".photo-grid-item")
  );
  if (links.length === 0 || typeof HTMLDialogElement === "undefined") return;

  var dialog = document.createElement("dialog");
  dialog.className = "lightbox";
  dialog.innerHTML =
    '<button class="lightbox-close" aria-label="Close">&#215;</button>' +
    '<button class="lightbox-prev" aria-label="Previous photo">&#8592;</button>' +
    '<figure><img alt=""><figcaption></figcaption></figure>' +
    '<button class="lightbox-next" aria-label="Next photo">&#8594;</button>';
  document.body.appendChild(dialog);

  var image = dialog.querySelector("img");
  var caption = dialog.querySelector("figcaption");
  var index = 0;

  function show(i) {
    index = (i + links.length) % links.length;
    var link = links[index];
    var text = link.getAttribute("data-caption") || "";
    image.src = link.href;
    image.alt = text;
    caption.textContent = text;
    caption.hidden = text === "";
  }

  links.forEach(function (link, i) {
    link.addEventListener("click", function (event) {
      event.preventDefault();
      show(i);
      dialog.showModal();
    });
  });

  dialog.querySelector(".lightbox-close").addEventListener("click", function () {
    dialog.close();
  });
  dialog.querySelector(".lightbox-prev").addEventListener("click", function () {
    show(index - 1);
  });
  dialog.querySelector(".lightbox-next").addEventListener("click", function () {
    show(index + 1);
  });
  dialog.addEventListener("keydown", function (event) {
    if (event.key === "ArrowLeft") show(index - 1);
    if (event.key === "ArrowRight") show(index + 1);
  });
  dialog.addEventListener("click", function (event) {
    if (event.target === dialog) dialog.close();
  });
})();
