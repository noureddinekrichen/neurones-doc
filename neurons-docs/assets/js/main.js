/* Neurons documentation — page behaviour.
   Mobile drawer, navigation filter, "/" shortcut, active-section tracking (sidebar + right TOC)
   and the language selector. No dependencies; works on any page that uses the shared markup. */
(function(){
  'use strict';

  var LANG_KEY = 'neurons-lang';
  var drawerQuery = window.matchMedia('(max-width: 900px)');

  function toArray(list){ return Array.prototype.slice.call(list); }

  var sidebar = document.getElementById('sidebar');
  var overlay = document.getElementById('overlay');
  var navToggle = document.getElementById('navToggle');
  var navSearch = document.getElementById('navSearch');
  var navEmpty = document.getElementById('navEmpty');

  var navLinks = toArray(document.querySelectorAll('.nav-link'));
  var navGroups = toArray(document.querySelectorAll('.nav-group'));
  var tocGroups = toArray(document.querySelectorAll('.toc-group'));
  var tocLinks = toArray(document.querySelectorAll('.toc a'));
  var headings = toArray(document.querySelectorAll('main h2[id]'));

  var navById = {}, tocById = {};
  navLinks.forEach(function(a){ navById[a.getAttribute('href').slice(1)] = a; });
  tocLinks.forEach(function(a){ tocById[a.getAttribute('href').slice(1)] = a; });

  var currentHeadingId = null;

  /* ============ Mobile drawer (on desktop the sidebar is always visible) ============ */
  function firstVisibleNavLink(){
    for (var i = 0; i < navLinks.length; i++){
      if (!navLinks[i].hidden && !navLinks[i].parentNode.hidden) return navLinks[i];
    }
    return null;
  }
  function isSidebarOpen(){ return sidebar.classList.contains('open'); }
  function openSidebar(){
    sidebar.classList.add('open');
    overlay.classList.add('open');
    navToggle.setAttribute('aria-expanded', 'true');
    var target = sidebar.querySelector('.nav-link.active:not([hidden])') || firstVisibleNavLink();
    if (target) target.focus({ preventScroll: true });
  }
  function closeSidebar(returnFocus){
    if (!isSidebarOpen()) return;
    sidebar.classList.remove('open');
    overlay.classList.remove('open');
    navToggle.setAttribute('aria-expanded', 'false');
    if (returnFocus) navToggle.focus({ preventScroll: true });
  }
  navToggle.addEventListener('click', function(){
    isSidebarOpen() ? closeSidebar(true) : openSidebar();
  });
  overlay.addEventListener('click', function(){ closeSidebar(true); });
  navLinks.forEach(function(a){ a.addEventListener('click', function(){ closeSidebar(false); }); });
  var onDrawerQueryChange = function(e){ if (!e.matches) closeSidebar(false); };
  if (drawerQuery.addEventListener) drawerQuery.addEventListener('change', onDrawerQueryChange);
  else if (drawerQuery.addListener) drawerQuery.addListener(onDrawerQueryChange);

  /* ============ Navigation filter ============ */
  /* accent-insensitive so "evenements" matches "Événements" */
  function normalize(s){
    s = s.toLowerCase();
    return s.normalize ? s.normalize('NFD').replace(/[̀-ͯ]/g, '') : s;
  }
  navSearch.addEventListener('input', function(){
    var q = normalize(navSearch.value.trim());
    var anyVisible = false;
    navGroups.forEach(function(group){
      var groupHasMatch = false;
      toArray(group.querySelectorAll('.nav-link')).forEach(function(a){
        var match = !q || normalize(a.textContent).indexOf(q) !== -1;
        a.hidden = !match;
        if (match) groupHasMatch = true;
      });
      group.hidden = !groupHasMatch;
      if (groupHasMatch) anyVisible = true;
    });
    navEmpty.hidden = anyVisible;
  });
  /* Enter: jump to the first match on desktop; on mobile, open the drawer to show the matches */
  navSearch.addEventListener('keydown', function(e){
    if (e.key !== 'Enter') return;
    var first = firstVisibleNavLink();
    if (!first) return;
    e.preventDefault();
    if (drawerQuery.matches) { openSidebar(); }
    else { navSearch.blur(); first.click(); }
  });

  /* ============ Language selector ============ */
  var langDropdown = document.getElementById('langDropdown');
  var langCurrent = document.getElementById('langCurrent');
  var langMenu = document.getElementById('langMenu');
  var langOptions = toArray(langMenu.querySelectorAll('.lang-option'));

  function isLangMenuOpen(){ return langMenu.classList.contains('open'); }
  function openLangMenu(){
    langMenu.classList.add('open');
    langCurrent.setAttribute('aria-expanded', 'true');
    var active = langMenu.querySelector('.lang-option.active') || langOptions[0];
    if (active) active.focus({ preventScroll: true });
  }
  function closeLangMenu(returnFocus){
    if (!isLangMenuOpen()) return;
    langMenu.classList.remove('open');
    langCurrent.setAttribute('aria-expanded', 'false');
    if (returnFocus) langCurrent.focus({ preventScroll: true });
  }
  langCurrent.addEventListener('click', function(e){
    e.stopPropagation();
    isLangMenuOpen() ? closeLangMenu(false) : openLangMenu();
  });
  document.addEventListener('click', function(e){
    if (!langDropdown.contains(e.target)) closeLangMenu(false);
  });
  langDropdown.addEventListener('focusout', function(e){
    if (e.relatedTarget && !langDropdown.contains(e.relatedTarget)) closeLangMenu(false);
  });
  langOptions.forEach(function(opt){
    opt.addEventListener('click', function(e){
      var lang = opt.getAttribute('hreflang');
      try { localStorage.setItem(LANG_KEY, lang); } catch (err) {}
      e.preventDefault();
      if (lang === document.documentElement.lang){ closeLangMenu(true); return; }
      /* keep the reader on the same section in the other language */
      var base = opt.getAttribute('href').split('#')[0];
      location.href = base + (currentHeadingId ? '#' + currentHeadingId : '');
    });
  });

  /* ============ Keyboard shortcuts ============ */
  function isEditable(el){
    if (!el) return false;
    var tag = el.tagName;
    return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || el.isContentEditable;
  }
  document.addEventListener('keydown', function(e){
    if (e.key === '/' && !e.ctrlKey && !e.metaKey && !e.altKey && !isEditable(document.activeElement)){
      e.preventDefault();
      navSearch.focus();
    } else if (e.key === 'Escape'){
      if (isLangMenuOpen()) closeLangMenu(true);
      else if (isSidebarOpen()) closeSidebar(true);
      else if (document.activeElement === navSearch) navSearch.blur();
    }
  });

  /* ============ Active section tracking ============ */
  function setActiveHeading(id){
    currentHeadingId = id;
    navLinks.forEach(function(a){ a.classList.remove('active'); a.removeAttribute('aria-current'); });
    tocLinks.forEach(function(a){ a.classList.remove('active'); a.removeAttribute('aria-current'); });
    if (navById[id]) { navById[id].classList.add('active'); navById[id].setAttribute('aria-current', 'location'); }
    if (tocById[id]) { tocById[id].classList.add('active'); tocById[id].setAttribute('aria-current', 'location'); }
  }
  function setActivePart(part){
    tocGroups.forEach(function(g){
      g.classList.toggle('active', g.getAttribute('data-toc-part') === part);
    });
  }

  /* The active section is the last heading that has scrolled past the top quarter of the
     viewport. Computed from scroll position (not intersection events) so it is correct in
     both scroll directions, after anchor jumps and on reload; the TOC always shows the part
     that contains the active heading. */
  function headingPart(h){
    var part = h.closest ? h.closest('.doc-part') : null;
    return part ? part.getAttribute('data-part') : null;
  }
  function updateActiveFromScroll(){
    if (!headings.length) return;
    var threshold = window.innerHeight * 0.25;
    var current = headings[0];
    for (var i = 0; i < headings.length; i++){
      if (headings[i].getBoundingClientRect().top <= threshold) current = headings[i];
      else break;
    }
    if (current.id !== currentHeadingId){
      setActiveHeading(current.id);
      setActivePart(headingPart(current));
    }
  }
  var scrollScheduled = false;
  function scheduleUpdate(){
    if (scrollScheduled) return;
    scrollScheduled = true;
    window.requestAnimationFrame(function(){ scrollScheduled = false; updateActiveFromScroll(); });
  }
  window.addEventListener('scroll', scheduleUpdate, { passive: true });
  window.addEventListener('resize', scheduleUpdate);
  window.addEventListener('hashchange', scheduleUpdate);
  window.addEventListener('load', scheduleUpdate);
  updateActiveFromScroll();
})();
