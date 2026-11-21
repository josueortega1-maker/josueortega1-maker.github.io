const menuButton = document.querySelector('.menu-button');
const navigation = document.querySelector('#site-nav');

menuButton?.addEventListener('click', () => {
  const isOpen = navigation.classList.toggle('open');
  menuButton.setAttribute('aria-expanded', String(isOpen));
});

navigation?.querySelectorAll('a').forEach((link) => {
  link.addEventListener('click', () => {
    navigation.classList.remove('open');
    menuButton?.setAttribute('aria-expanded', 'false');
  });
});

document.querySelector('#year').textContent = String(new Date().getFullYear());


// Microsoft Clarity: load only after an explicit choice to allow analytics.
// Consent is stored locally so a returning visitor is not prompted each time.
(() => {
  const storageKey = 'josue-analytics-consent-v1';
  const notice = document.querySelector('#analytics-consent');
  const settings = document.querySelector('#analytics-settings');
  const allow = document.querySelector('#analytics-allow');
  const decline = document.querySelector('#analytics-decline');
  if (!notice || !settings || !allow || !decline) return;

  let clarityStarted = false;

  const savedChoice = () => {
    try { return window.localStorage.getItem(storageKey); }
    catch { return null; }
  };

  const saveChoice = (value) => {
    try { window.localStorage.setItem(storageKey, value); }
    catch { /* When storage is unavailable, consent lasts only this visit. */ }
  };

  const startClarity = () => {
    if (clarityStarted) return;
    clarityStarted = true;

    // This is the Microsoft-provided tracking snippet, gated by consent.
    (function(c,l,a,r,i,t,y){
      c[a]=c[a]||function(){(c[a].q=c[a].q||[]).push(arguments)};
      t=l.createElement(r);t.async=1;t.src="https://www.clarity.ms/tag/"+i;
      y=l.getElementsByTagName(r)[0];y.parentNode.insertBefore(t,y);
    })(window, document, "clarity", "script", "zhb2nzmulu");

    // Consent API v2 is required for full Clarity functionality in UK/EEA.
    // This website does not request advertising-storage consent.
    window.clarity('consentv2', {
      ad_Storage: 'denied',
      analytics_Storage: 'granted'
    });
  };

  const choose = (choice) => {
    saveChoice(choice);
    notice.hidden = true;
    if (choice === 'allow') {
      startClarity();
    } else if (clarityStarted) {
      // Revoke consent and reload to stop the already loaded tracker.
      window.clarity('consentv2', {
        ad_Storage: 'denied',
        analytics_Storage: 'denied'
      });
      window.setTimeout(() => window.location.reload(), 300);
    }
  };

  allow.addEventListener('click', () => choose('allow'));
  decline.addEventListener('click', () => choose('decline'));
  settings.addEventListener('click', () => {
    notice.hidden = false;
    allow.focus();
  });

  // Do not show a consent popup on arrival. Visitors can opt in by
  // selecting “Privacy & analytics” in the footer at any time.
  const choice = savedChoice();
  if (choice === 'allow') startClarity();
})();
