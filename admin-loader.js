(function () {
  const href = '/static/analytics/question-analytics-dashboard.html';
  let isAdmin = false;
  let checking = false;

  function removeAnalyticsEntry() {
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
    const link = document.createElement('a');
    link.id = 'admin-analytics-entry';
    link.href = href;
    link.textContent = '问题分析';
    link.style.cssText = [
      'position:fixed',
      'right:18px',
      'top:82px',
      'z-index:9999',
      'background:#111827',
      'color:#fff',
      'text-decoration:none',
      'font-size:13px',
      'font-weight:700',
      'padding:9px 12px',
      'border-radius:7px',
      'box-shadow:0 8px 22px rgba(15,23,42,.16)'
    ].join(';');
    document.body.appendChild(link);
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
