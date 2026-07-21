---
layout: home
title: Albert _________.
---

- [Photography](/ph.html)
- [Writing](/writing.html)
- [Projects](/projects.html)
- -
- [Instagram](https://instagram.com/a.l.b.e.r.t.c)
- [GitHub](https://github.com/acornelissen)
- [LinkedIn](https://www.linkedin.com/in/acornelissen/)
- -
- [IDENTIDEM.design](https://identidem.design)

{% assign highlight_ids = "lf-portraits-close|mf-misc|instant-fp100c" | split: "|" %}
<div class="home-highlights">
  {% for id in highlight_ids %}
  {% assign gallery = site.data.galleries | where: "id", id | first %}
  <a href="{{ gallery.url }}" aria-label="Photography: {{ gallery.section }} / {{ gallery.title }}">
    <img src="{{ gallery.dir }}{{ gallery.cover }}" alt="" loading="lazy" decoding="async">
  </a>
  {% endfor %}
</div>
