// SPDX-License-Identifier: AGPL-3.0-or-later

(() => {
  function gameOverModal() {
    return document.querySelector('.game-over-modal[role="dialog"]');
  }

  function focusableElements(modal) {
    return [...modal.querySelectorAll('button, [href], input, select, textarea, [tabindex]')]
      .filter((element) =>
        !element.disabled
          && element.type !== 'hidden'
          && element.tabIndex >= 0
          && element.getClientRects().length > 0);
  }

  function focusGameOverModal() {
    const modal = gameOverModal();
    if (!modal) {
      return;
    }

    const firstFocusable = focusableElements(modal)[0];
    if (firstFocusable && !modal.contains(document.activeElement)) {
      firstFocusable.focus({ preventScroll: true });
    }
  }

  function keepFocusInGameOverModal(event) {
    const modal = gameOverModal();
    if (!modal || modal.contains(event.target)) {
      return;
    }

    const firstFocusable = focusableElements(modal)[0];
    if (firstFocusable) {
      firstFocusable.focus({ preventScroll: true });
    }
  }

  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Tab') {
      return;
    }

    const modal = gameOverModal();
    if (!modal) {
      return;
    }

    const focusables = focusableElements(modal);
    if (focusables.length === 0) {
      event.preventDefault();
      return;
    }

    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    const active = document.activeElement;

    if (!modal.contains(active)) {
      event.preventDefault();
      first.focus({ preventScroll: true });
    } else if (event.shiftKey && active === first) {
      event.preventDefault();
      last.focus({ preventScroll: true });
    } else if (!event.shiftKey && active === last) {
      event.preventDefault();
      first.focus({ preventScroll: true });
    }
  }, true);

  document.addEventListener('focusin', keepFocusInGameOverModal);
  document.addEventListener('DOMContentLoaded', focusGameOverModal);
  document.addEventListener('htmx:afterSwap', focusGameOverModal);
})();
