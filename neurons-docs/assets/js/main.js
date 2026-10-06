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

  /* only links to sections of this page take part in active-section tracking */
  var navById = {}, tocById = {};
  navLinks.forEach(function(a){
    var href = a.getAttribute('href');
    if (href.charAt(0) === '#') navById[href.slice(1)] = a;
  });
  tocLinks.forEach(function(a){ tocById[a.getAttribute('href').slice(1)] = a; });

  var currentHeadingId = null;

  /* ============ Mobile drawer (on desktop the sidebar is always visible) ============ */
  function firstVisibleNavLink(){
    for (var i = 0; i < navLinks.length; i++){
      if (navLinks[i].offsetParent !== null) return navLinks[i];
    }
    return null;
  }
  function isSidebarOpen(){ return sidebar.classList.contains('open'); }
  function openSidebar(){
    sidebar.classList.add('open');
    overlay.classList.add('open');
    navToggle.setAttribute('aria-expanded', 'true');
    var active = sidebar.querySelector('.nav-link.active');
    var target = (active && active.offsetParent !== null) ? active : firstVisibleNavLink();
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

  /* ============ Collapsible groups ============ */
  /* Every group/category starts open (as rendered by the template). A group the reader closes stays
     closed, and one they reopen stays open, for the browser session and across pages. */
  var NAV_STATE_KEY = 'neurons-nav';
  var navList = document.getElementById('navList');
  var collapsibles = toArray(navList.querySelectorAll('.nav-group, .nav-sub')).filter(function(node){
    return node.firstElementChild && node.firstElementChild.tagName === 'BUTTON';
  });
  var navState = {};
  try { navState = JSON.parse(sessionStorage.getItem(NAV_STATE_KEY)) || {}; } catch (err) {}
  function isOpen(node){
    return navState[node.getAttribute('data-group')] !== false;
  }
  function applyCollapse(){
    collapsibles.forEach(function(node){
      var open = isOpen(node);
      node.classList.toggle('is-collapsed', !open);
      node.firstElementChild.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  }
  collapsibles.forEach(function(node){
    node.firstElementChild.addEventListener('click', function(){
      navState[node.getAttribute('data-group')] = node.classList.contains('is-collapsed');
      try { sessionStorage.setItem(NAV_STATE_KEY, JSON.stringify(navState)); } catch (err) {}
      applyCollapse();
    });
  });
  applyCollapse();

  /* ============ Navigation filter ============ */
  /* accent-insensitive so "evenements" matches "Événements" */
  function normalize(s){
    s = s.toLowerCase();
    return s.normalize ? s.normalize('NFD').replace(/[\u0300-\u036f]/g, '') : s;
  }
  navSearch.addEventListener('input', function(){
    var q = normalize(navSearch.value.trim());
    var anyVisible = false;
    navList.classList.toggle('is-filtering', !!q);  /* matches are shown even in closed groups */
    navGroups.forEach(function(group){
      var groupHasMatch = false;
      toArray(group.querySelectorAll('.nav-link')).forEach(function(a){
        /* data-search: extra words a link answers to (e.g. its sidebar group and category) */
        var text = a.textContent + ' ' + (a.getAttribute('data-search') || '');
        var match = !q || normalize(text).indexOf(q) !== -1;
        a.hidden = !match;
        if (match) groupHasMatch = true;
      });
      /* a sub-category label is shown only while one of its links is */
      toArray(group.querySelectorAll('.nav-sub')).forEach(function(sub){
        sub.hidden = !sub.querySelector('.nav-link:not([hidden])');
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
      navSearch.focus({ preventScroll: true });
    } else if (e.key === 'Escape'){
      if (isLangMenuOpen()) closeLangMenu(true);
      else if (isSidebarOpen()) closeSidebar(true);
      else if (document.activeElement === navSearch) navSearch.blur();
    }
  });

  /* ============ Active section tracking ============ */
  var reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  var toc = document.getElementById('toc');

  /* Scroll a panel (sidebar or TOC, which scroll on their own) so that `el` is comfortably in view.
     Only the panel moves, never the page. */
  function keepInView(panel, el){
    if (!panel || !el || el.offsetParent === null) return;
    var p = panel.getBoundingClientRect(), r = el.getBoundingClientRect(), margin = 40;
    if (r.top >= p.top + margin && r.bottom <= p.bottom - margin) return;
    var top = panel.scrollTop + (r.top - p.top) - p.height / 3;
    if (panel.scrollTo) panel.scrollTo({ top: top, behavior: reducedMotion.matches ? 'auto' : 'smooth' });
    else panel.scrollTop = top;
  }

  /* Only links to sections of this page are (de)highlighted here; a link to the current page
     (e.g. PHP in the sidebar while reading the PHP page) keeps its highlight. */
  var trackedNav = Object.keys(navById).map(function(id){ return navById[id]; });
  function setActiveHeading(id){
    currentHeadingId = id;
    trackedNav.forEach(function(a){ a.classList.remove('active'); a.removeAttribute('aria-current'); });
    tocLinks.forEach(function(a){ a.classList.remove('active'); a.removeAttribute('aria-current'); });
    if (navById[id]) { navById[id].classList.add('active'); navById[id].setAttribute('aria-current', 'location'); }
    if (tocById[id]) { tocById[id].classList.add('active'); tocById[id].setAttribute('aria-current', 'location'); }
    keepInView(sidebar, navById[id]);
    keepInView(toc, tocById[id]);
  }
  function setActivePart(part){
    tocGroups.forEach(function(g){
      g.classList.toggle('active', g.getAttribute('data-toc-part') === part);
    });
  }

  /* The active section is the last heading that has scrolled past the top quarter of the
     viewport. Computed from scroll position (not intersection events) so it is correct in
     both scroll directions, after anchor jumps and on reload; the TOC always shows the part
     that contains the active heading. At the very bottom of the page, short final sections
     can never reach that line: there the linked section (URL #hash) if visible, otherwise
     the last visible heading, is active. */
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
    var doc = document.documentElement;
    if (window.innerHeight + window.pageYOffset >= doc.scrollHeight - 2){
      var visible = headings.filter(function(h){
        var top = h.getBoundingClientRect().top;
        return top >= 0 && top < window.innerHeight;
      });
      var target = location.hash ? document.getElementById(decodeURIComponent(location.hash.slice(1))) : null;
      if (target && visible.indexOf(target) !== -1) current = target;
      else if (visible.length) current = visible[visible.length - 1];
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
  /* Smooth scrolling (see main.css) starts with the reader's first interaction: in-page link clicks
     always follow one, while the browser's initial jump to a #section never does, so it stays instant. */
  function enableSmoothScroll(){
    document.documentElement.classList.add('smooth-scroll');
    ['pointerdown', 'keydown', 'wheel', 'touchstart'].forEach(function(t){ window.removeEventListener(t, enableSmoothScroll, true); });
  }
  ['pointerdown', 'keydown', 'wheel', 'touchstart'].forEach(function(t){ window.addEventListener(t, enableSmoothScroll, { capture: true, passive: true }); });
  updateActiveFromScroll();
  /* a page highlighted in the sidebar by the template (e.g. PHP on its own page) */
  keepInView(sidebar, sidebar.querySelector('.nav-link[aria-current="page"]'));
})();
