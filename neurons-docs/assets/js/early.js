/* Runs synchronously in the <head> of every page, before the page is painted.
   1. Marks that JavaScript is available (html.js): the collapsible sidebar groups are only
      collapsed then, so without JavaScript everything stays open.
   2. Default-language (English) pages only — the script tag carries data-<lang>="…" with this
      page's URL in the other languages: if the visitor previously chose another language in the
      language selector, go to this page's translation. Explicit language URLs are never redirected. */
(function(){
  document.documentElement.classList.add('js');
  try {
    var lang = localStorage.getItem('neurons-lang');
    var target = lang && document.currentScript && document.currentScript.getAttribute('data-' + lang);
    if (target) location.replace(target + location.hash);
  } catch (e) {}
})();
