(function () {
  const href = '/static/analytics/question-analytics-dashboard.html';
  let isAdmin = false;
  let checking = false;

  function removeAnalyticsEntry() {
    document.getElementById('admin-analytics-entry-row')?.remove();
    document.getElementById('admin-analytics-entry')?.remove();
  }

  function isAuthPage() {
    return location.pathname.startsWith('/auth');
  }

  function renderAnalyticsEntry() {
    if (!isAdmin || isAuthPage()) {
      removeAnalyticsEntry();
      return;
    }
    if (document.getElementById('admin-analytics-entry')) return;
    const workspaceLink = document.querySelector('a[href="/workspace"]');
    if (!workspaceLink) return;
    const link = workspaceLink.cloneNode(true);
    link.id = 'admin-analytics-entry';
    link.href = href;
    link.removeAttribute('aria-current');
    link.innerHTML = `
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24"
        fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"
        stroke-linejoin="round" aria-hidden="true">
        <path d="M3 3v18h18"></path>
        <path d="m7 16 4-4 3 3 5-7"></path>
      </svg>
      <span>问题分析</span>
    `;
    const row = workspaceLink.parentElement;
    if (row && row.children.length === 1) {
      const analyticsRow = row.cloneNode(false);
      analyticsRow.id = 'admin-analytics-entry-row';
      analyticsRow.appendChild(link);
      row.insertAdjacentElement('afterend', analyticsRow);
    } else {
      workspaceLink.insertAdjacentElement('afterend', link);
    }
  }

  async function checkAdmin() {
    if (checking) return;
    checking = true;
    try {
      const response = await fetch('/api/v1/auths/', {
        credentials: 'same-origin',
        headers: { Accept: 'application/json' }
      });
      const user = response.ok ? await response.json() : null;
      isAdmin = user?.role === 'admin';
    } catch (_) {
      isAdmin = false;
    } finally {
      checking = false;
      renderAnalyticsEntry();
    }
  }

  function init() {
    removeAnalyticsEntry();
    checkAdmin();
    new MutationObserver(renderAnalyticsEntry).observe(document.body || document.documentElement, {
      childList: true,
      subtree: true
    });
    window.addEventListener('popstate', () => {
      removeAnalyticsEntry();
      checkAdmin();
    });
    setInterval(checkAdmin, 30000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
