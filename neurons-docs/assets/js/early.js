/* Loaded synchronously in the <head> of the English page only.
   If the visitor previously chose French in the language selector, send them to the French
   page before the English one paints. Explicit language URLs (e.g. /neurons/fr/) are never redirected. */
(function(){
  try {
    if (localStorage.getItem('neurons-lang') === 'fr') {
      location.replace('fr/' + location.hash);
    }
  } catch (e) {}
})();
