---
layout: home
title: Albert takes pictures.
---

{% include breadcrumbs.html current="Photography" %}

{% assign sections = site.data.galleries | map: "section" | uniq %}
{% for section in sections %}
<section class="gallery-section">
  <h4>{{ section }}</h4>
  <ul class="gallery-index">
    {% for gallery in site.data.galleries %}{% if gallery.section == section %}
    {% assign photos = site.static_files | where_exp: "f", "f.path contains gallery.dir" | where_exp: "f", "f.extname == '.jpg'" %}
    {% assign cover_dir = gallery.dir | replace_first: "/assets/", "/assets/thumbs/" %}
    <li>
      <a href="{{ gallery.url }}">
        <img class="gallery-index-cover" src="{{ cover_dir }}{{ gallery.cover }}" alt="" loading="lazy" decoding="async">
        <span class="gallery-index-text">
          <span class="gallery-index-title">{{ gallery.title }}</span>
          <span class="gallery-index-count">{{ photos | size }} photos</span>
        </span>
      </a>
    </li>
    {% endif %}{% endfor %}
  </ul>
</section>
{% endfor %}
