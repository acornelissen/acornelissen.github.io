---
layout: default
title: Albert takes pictures.
---

<h1 class="page-title">Albert takes pictures.</h1>

<div class="hub-sections">
{% assign sections = site.data.galleries | map: "section" | uniq %}
{% for section in sections %}
<section class="gallery-section">
  <h2>{{ section }}</h2>
  <ul class="gallery-index">
    {% for gallery in site.data.galleries %}{% if gallery.section == section %}
    {% assign cover_dir = gallery.dir | replace_first: "/assets/", "/assets/thumbs/" %}
    <li>
      <a href="{{ gallery.url }}">
        <img class="gallery-index-cover" src="{{ cover_dir }}{{ gallery.cover }}" alt="" loading="lazy" decoding="async">
        <span class="gallery-index-title">{{ gallery.title }}</span>
      </a>
    </li>
    {% endif %}{% endfor %}
  </ul>
</section>
{% endfor %}
</div>
