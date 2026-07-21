---
layout: default
title: Albert tinkers.
---

<h1 class="page-title">Albert tinkers.</h1>

<ul class="projects-list">
  {% for project in site.data.projects %}
  <li>
    <a href="{{ project.url }}" target="_blank" rel="noopener">
      <span>
        <span class="project-name">{{ project.name }}</span>
        <span class="project-tech">{{ project.tech }}</span>
      </span>
      <span>
        <span class="project-description">{{ project.description | escape }}</span>
        {% if project.stars %}<span class="project-stars">&#9733; {{ project.stars }} on GitHub</span>{% endif %}
      </span>
    </a>
  </li>
  {% endfor %}
</ul>

<p class="projects-more">More on <a href="https://github.com/acornelissen">GitHub</a> and at <a href="https://identidem.design">IDENTIDEM.design</a>.</p>
