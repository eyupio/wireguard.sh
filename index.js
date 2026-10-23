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
})();
