---
layout: home
title: Albert tinkers.
---

{% include breadcrumbs.html current="Projects" %}

<ul class="projects-list">
  {% for project in site.data.projects %}
  <li>
    <h4><a href="{{ project.url }}">{{ project.name }}</a></h4>
    <p class="project-meta">{{ project.tech }}{% if project.stars %} &middot; {{ project.stars }} stars on GitHub{% endif %}</p>
    <p class="project-description">{{ project.description | escape }}</p>
  </li>
  {% endfor %}
</ul>

More on [GitHub](https://github.com/acornelissen) and at [IDENTIDEM.design](https://identidem.design).
