(function () {
  const analyticsEntries = [
    {
      id: 'admin-analytics-entry',
      href: '/static/analytics/question-analytics-dashboard.html',
      label: '问题分析',
      icon: '<path d="M3 3v18h18"></path><path d="m7 16 4-4 3 3 5-7"></path>'
    },
    {
      id: 'admin-visit-analytics-entry',
      href: '/static/analytics/access-analytics-dashboard.html',
      label: '访问统计',
      icon: '<path d="M3 3v18h18"></path><path d="M7 16v-5"></path><path d="M12 16V8"></path><path d="M17 16v-9"></path>'
    }
  ];
  let isAdmin = false;
  let checking = false;

  function removeAnalyticsEntry() {
    analyticsEntries.forEach(({ id }) => {
      document.getElementById(`${id}-row`)?.remove();
      document.getElementById(id)?.remove();
    });
  }

  function isAuthPage() {
    return location.pathname.startsWith('/auth');
  }

  function setDefaultKnowledgeAccess() {
    if (location.pathname !== '/workspace/knowledge/create') return;
    const select = document.querySelector('select#models');
    if (!select || select.dataset.defaultAccessApplied === 'true') return;
    const publicOption = Array.from(select.options).find((option) => {
      const label = option.textContent.trim().toLowerCase();
      const value = option.value.toLowerCase();
      return label === '公共' || label === 'public' || value === 'public';
    });
    if (!publicOption) return;
    select.dataset.defaultAccessApplied = 'true';
    if (select.value === publicOption.value) return;
    const valueSetter = Object.getOwnPropertyDescriptor(
      HTMLSelectElement.prototype,
      'value'
    )?.set;
    valueSetter?.call(select, publicOption.value);
    select.dispatchEvent(new Event('input', { bubbles: true }));
    select.dispatchEvent(new Event('change', { bubbles: true }));
  }

  function renderAnalyticsEntry() {
    setDefaultKnowledgeAccess();
    if (!isAdmin || isAuthPage()) {
      removeAnalyticsEntry();
      return;
    }
    const workspaceLink = document.querySelector('a[href="/workspace"]');
    if (!workspaceLink) return;
    const row = workspaceLink.parentElement;
    let anchor = row || workspaceLink;
    analyticsEntries.forEach((entry) => {
      if (document.getElementById(entry.id)) {
        anchor = document.getElementById(`${entry.id}-row`) || document.getElementById(entry.id);
        return;
      }
      const link = workspaceLink.cloneNode(true);
      link.id = entry.id;
      link.href = entry.href;
      link.removeAttribute('aria-current');
      link.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24"
          fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"
          stroke-linejoin="round" aria-hidden="true">${entry.icon}</svg>
        <span>${entry.label}</span>
      `;
      if (row && row.children.length === 1) {
        const analyticsRow = row.cloneNode(false);
        analyticsRow.id = `${entry.id}-row`;
        analyticsRow.appendChild(link);
        anchor.insertAdjacentElement('afterend', analyticsRow);
        anchor = analyticsRow;
      } else {
        anchor.insertAdjacentElement('afterend', link);
        anchor = link;
      }
    });
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
