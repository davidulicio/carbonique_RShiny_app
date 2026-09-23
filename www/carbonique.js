/* CARBONIQUE data explorer: language switch (French / English)
 *
 * Static text carries data-i18n="key"; this script swaps it using the
 * dictionary in window.CQ_I18N (written by app.R from functions/i18n.R).
 * The current language is also a Shiny input (input$lang), so plots and
 * messages built on the server follow it without reloading the page.
 * Choice order: ?lang=fr|en in the URL, then the last choice on this browser,
 * then the browser language.
 */
(function () {
  "use strict";
  var DICT = window.CQ_I18N || { en: {}, fr: {} };

  function detect() {
    try {
      var q = new URLSearchParams(window.location.search).get("lang");
      if (q === "fr" || q === "en") return q;
    } catch (e) {}
    try {
      var s = window.localStorage.getItem("cq-lang");
      if (s === "fr" || s === "en") return s;
    } catch (e) {}
    var n = (navigator.language || "en").toLowerCase();
    return n.indexOf("fr") === 0 ? "fr" : "en";
  }

  window.CQ_LANG = detect();
  document.documentElement.lang = window.CQ_LANG;

  function apply(lang) {
    var d = DICT[lang] || DICT.en;
    var nodes = document.querySelectorAll("[data-i18n]");
    for (var i = 0; i < nodes.length; i++) {
      var k = nodes[i].getAttribute("data-i18n");
      if (typeof d[k] === "string" && nodes[i].textContent !== d[k]) nodes[i].textContent = d[k];
    }
    document.documentElement.lang = lang;
    if (d.app_title) document.title = "CARBONIQUE · " + d.app_title;
    var btns = document.querySelectorAll(".cq-lang-toggle button");
    for (var j = 0; j < btns.length; j++) {
      var on = btns[j].getAttribute("data-lang") === lang;
      btns[j].classList.toggle("active", on);
      btns[j].setAttribute("aria-pressed", on ? "true" : "false");
    }
  }

  function setLang(lang) {
    if (lang === window.CQ_LANG) return;
    window.CQ_LANG = lang;
    try { window.localStorage.setItem("cq-lang", lang); } catch (e) {}
    apply(lang);
    if (window.jQuery) window.jQuery(".cq-lang-toggle").trigger("cq:langchange");
  }

  document.addEventListener("DOMContentLoaded", function () {
    apply(window.CQ_LANG);
    document.addEventListener("click", function (ev) {
      var b = ev.target.closest && ev.target.closest(".cq-lang-toggle button");
      if (b) setLang(b.getAttribute("data-lang"));
    });
  });

  // Input binding: input$lang is known from the first server render
  if (window.Shiny && window.jQuery) {
    var $ = window.jQuery;
    var binding = new window.Shiny.InputBinding();
    $.extend(binding, {
      find: function (scope) { return $(scope).find(".cq-lang-toggle"); },
      getValue: function () { return window.CQ_LANG; },
      subscribe: function (el, callback) { $(el).on("cq:langchange.cq", function () { callback(); }); },
      unsubscribe: function (el) { $(el).off(".cq"); }
    });
    window.Shiny.inputBindings.register(binding, "carbonique.langToggle");

    // Text inside UI that the server re-renders (and plots) keeps the language
    $(document).on("shiny:value", function () { setTimeout(function () { apply(window.CQ_LANG); }, 0); });
    // Plotly redraws with the right size when a tab becomes visible
    $(document).on("shown.bs.tab", function () { window.dispatchEvent(new Event("resize")); });
  }
})();
