(function () {
  'use strict';

  var status = document.getElementById('copy-status');
  var timers = new WeakMap();

  function fallbackCopy(text) {
    var area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.setAttribute('aria-hidden', 'true');
    area.style.position = 'fixed';
    area.style.top = '-1000px';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();

    var copied = false;
    try {
      copied = document.execCommand('copy');
    } catch (error) {
      copied = false;
    }

    area.remove();
    return copied;
  }

  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text).then(
        function () {
          return true;
        },
        function () {
          return fallbackCopy(text);
        }
      );
    }

    return Promise.resolve(fallbackCopy(text));
  }

  function announce(message) {
    if (!status) return;
    status.textContent = '';
    window.setTimeout(function () {
      status.textContent = message;
    }, 50);
  }

  function resetButton(button, label, text) {
    button.removeAttribute('data-state');
    label.textContent = text;
    announce('');
  }

  document.querySelectorAll('[data-copy]').forEach(function (button) {
    var target = document.getElementById(button.getAttribute('data-copy'));
    var label = button.querySelector('.copy__label');
    if (!target || !label) return;

    var defaultLabel = label.textContent;

    button.addEventListener('click', function () {
      var text = target.textContent.trim();

      copyText(text).then(function (copied) {
        if (copied) {
          button.setAttribute('data-state', 'success');
          label.textContent = 'Copied';
          announce('Command copied to clipboard.');
        } else {
          button.setAttribute('data-state', 'error');
          label.textContent = 'Copy failed';
          announce('Copy failed. Select the command and copy it manually.');
        }

        window.clearTimeout(timers.get(button));
        timers.set(
          button,
          window.setTimeout(function () {
            resetButton(button, label, defaultLabel);
          }, 2200)
        );
      });
    });
  });

  var RELEASE_API = 'https://api.github.com/repos/eyupio/wireguard.sh/releases/latest';
  var RELEASE_CACHE_KEY = 'wireguard.sh:latest-release';
  var RELEASE_CACHE_TTL = 60 * 60 * 1000;

  function applyRelease(release) {
    if (!release || !release.tag_name || !release.html_url) return;
    if (release.html_url.indexOf('https://github.com/eyupio/wireguard.sh/releases/') !== 0) return;

    document.querySelectorAll('[data-release-version]').forEach(function (node) {
      node.textContent = release.tag_name;
    });

    document.querySelectorAll('[data-release-link]').forEach(function (link) {
      link.setAttribute('href', release.html_url);
      link.setAttribute('aria-label', 'View release ' + release.tag_name + ' on GitHub');
    });
  }

  function readCachedRelease() {
    try {
      var raw = window.sessionStorage.getItem(RELEASE_CACHE_KEY);
      if (!raw) return null;
      var cached = JSON.parse(raw);
      if (!cached || !cached.savedAt || !cached.release) return null;
      if (Date.now() - cached.savedAt > RELEASE_CACHE_TTL) return null;
      return cached.release;
    } catch (error) {
      return null;
    }
  }

  function cacheRelease(release) {
    try {
      window.sessionStorage.setItem(
        RELEASE_CACHE_KEY,
        JSON.stringify({ savedAt: Date.now(), release: release })
      );
    } catch (error) {
      return;
    }
  }

  function loadLatestRelease() {
    if (typeof window.fetch !== 'function') return;

    var cached = readCachedRelease();
    if (cached) {
      applyRelease(cached);
      return;
    }

    var controller = typeof window.AbortController === 'function' ? new window.AbortController() : null;
    var timer = controller
      ? window.setTimeout(function () {
          controller.abort();
        }, 8000)
      : null;

    window
      .fetch(RELEASE_API, {
        headers: { Accept: 'application/vnd.github+json' },
        signal: controller ? controller.signal : undefined,
      })
      .then(function (response) {
        if (!response.ok) return null;
        return response.json();
      })
      .then(function (release) {
        if (!release) return;
        applyRelease(release);
        cacheRelease(release);
      })
      .catch(function () {
        return;
      })
      .then(function () {
        if (timer) window.clearTimeout(timer);
      });
  }

  loadLatestRelease();
})();
