(function () {
  'use strict';

  var BTN_ID = 'ssbconfig-leftmenu-link';
  var STYLE_ID = 'ssbconfig-leftmenu-style';
  var TARGET_URL = 'pluginadmin.ashx?pin=ssbconfig';

  function findNativePluginEntry() {
    var selectors = [
      '[href*="pin=ssbconfig"]',
      '[onclick*="ssbconfig"]',
      '[data-pin="ssbconfig"]',
      '[data-plugin="ssbconfig"]'
    ];

    for (var i = 0; i < selectors.length; i++) {
      var nodes = document.querySelectorAll(selectors[i]);
      for (var j = 0; j < nodes.length; j++) {
        var node = nodes[j];
        if (!node || node.id === BTN_ID) continue;
        if (node.closest && node.closest('#' + BTN_ID)) continue;
        return node;
      }
    }

    return null;
  }

  function openInMeshCentralFrame(evt) {
    if (evt) {
      evt.preventDefault();
      evt.stopPropagation();
    }

    var nativeEntry = findNativePluginEntry();
    if (nativeEntry) {
      try {
        nativeEntry.dispatchEvent(new MouseEvent('click', {
          view: window,
          bubbles: true,
          cancelable: true
        }));
        return;
      } catch (e) {
        // Fall back below.
      }

      if (typeof nativeEntry.click === 'function') {
        nativeEntry.click();
        return;
      }

      if (nativeEntry.getAttribute) {
        var href = nativeEntry.getAttribute('href');
        if (href && href !== '#' && href.indexOf('javascript:') !== 0) {
          window.location.assign(href);
          return;
        }
      }
    }

    window.location.assign(TARGET_URL);
  }

  function injectStyle() {
    if (document.getElementById(STYLE_ID)) return;
    var style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = [
      '#' + BTN_ID + ' {',
      '  width: 42px;',
      '  height: 42px;',
      '  border-radius: 8px;',
      '  display: flex;',
      '  align-items: center;',
      '  justify-content: center;',
      '  margin: 8px auto;',
      '  text-decoration: none;',
      '  background: linear-gradient(180deg, #2f80ed 0%, #1c5eb4 100%);',
      '  box-shadow: inset 0 1px 0 rgba(255,255,255,0.35), 0 1px 2px rgba(0,0,0,0.25);',
      '  transition: transform 120ms ease, filter 120ms ease;',
      '}',
      '#' + BTN_ID + ':hover {',
      '  transform: translateY(-1px);',
      '  filter: brightness(1.08);',
      '}',
      '#' + BTN_ID + ':active {',
      '  transform: translateY(0);',
      '}',
      '#' + BTN_ID + ' svg {',
      '  width: 22px;',
      '  height: 22px;',
      '  fill: #ffffff;',
      '}',
      '#ssbconfig-leftmenu-fallback {',
      '  position: fixed;',
      '  left: 8px;',
      '  bottom: 12px;',
      '  z-index: 1000;',
      '}',
      '#ssbconfig-leftmenu-fallback #' + BTN_ID + ' {',
      '  margin: 0;',
      '}',
      '#ssbconfig-leftmenu-fallback-label {',
      '  color: #5f6b76;',
      '  font: 11px/1.1 sans-serif;',
      '  margin-top: 4px;',
      '  text-align: center;',
      '}',
      '@media (max-width: 900px) {',
      '  #ssbconfig-leftmenu-fallback {',
      '    left: 4px;',
      '    bottom: 8px;',
      '  }',
      '}'
    ].join('\n');
    document.head.appendChild(style);
  }

  function buildButton() {
    var link = document.createElement('a');
    link.id = BTN_ID;
    link.href = TARGET_URL;
    link.title = 'Sikker Selvbetjening Config';
    link.setAttribute('aria-label', 'Open Sikker Selvbetjening Config');

    link.innerHTML = '' +
      '<svg viewBox="0 0 24 24" aria-hidden="true">' +
      '<path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z"/>' +
      '</svg>';

    link.addEventListener('click', openInMeshCentralFrame);

    return link;
  }

  function getMenuContainer() {
    var selectors = [
      '#column_l',
      '#leftbar',
      '.leftbar',
      '.leftColumn',
      '#MainMenuPanel'
    ];

    for (var i = 0; i < selectors.length; i++) {
      var candidate = document.querySelector(selectors[i]);
      if (candidate && candidate.offsetHeight > 100) return candidate;
    }

    return null;
  }

  function ensureButton() {
    if (document.getElementById(BTN_ID)) return;

    injectStyle();

    var button = buildButton();
    var menuContainer = getMenuContainer();

    if (menuContainer) {
      menuContainer.appendChild(button);
      return;
    }

    var fallback = document.getElementById('ssbconfig-leftmenu-fallback');
    if (!fallback) {
      fallback = document.createElement('div');
      fallback.id = 'ssbconfig-leftmenu-fallback';
      var label = document.createElement('div');
      label.id = 'ssbconfig-leftmenu-fallback-label';
      label.textContent = 'Config';
      fallback.appendChild(button);
      fallback.appendChild(label);
      document.body.appendChild(fallback);
    }
  }

  function start() {
    ensureButton();

    var observer = new MutationObserver(function () {
      ensureButton();
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
