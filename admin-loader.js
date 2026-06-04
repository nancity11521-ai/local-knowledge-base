(function () {
  const href = '/static/analytics/question-analytics-dashboard.html';

  function addAnalyticsEntry() {
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

  function init() {
    addAnalyticsEntry();
    new MutationObserver(addAnalyticsEntry).observe(document.body || document.documentElement, {
      childList: true,
      subtree: true
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
