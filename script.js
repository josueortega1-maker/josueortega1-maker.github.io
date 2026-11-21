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


// Microsoft Clarity: always send DENIED for analytics/ad storage.
// With Consent Mode enabled in the Clarity dashboard, page views and
// approximate visitor geography can still be reported without cookies.
// Never grant consent based on a prior stored choice.
(function(c,l,a,r,i,t,y) {
  c[a] = c[a] || function() {
    (c[a].q = c[a].q || []).push(arguments);
  };
  // Queue the denied consent signal BEFORE loading the tag.
  c[a]('consentv2', {
    ad_Storage: 'denied',
    analytics_Storage: 'denied'
  });
  t = l.createElement(r);
  t.async = 1;
  t.src = 'https://www.clarity.ms/tag/' + i;
  y = l.getElementsByTagName(r)[0];
  y.parentNode.insertBefore(t, y);
})(window, document, 'clarity', 'script', 'zhb2nzmulu');
