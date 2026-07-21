---
layout: default
title: Albert writes.
---

<h1 class="page-title">Albert writes.</h1>

<ul class="writing-index">
  {% for post in site.data.writing %}
  <li><a href="{{ post.url }}">{{ post.title }}</a></li>
  {% endfor %}
</ul>
