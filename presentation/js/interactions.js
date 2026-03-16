/* ============================================================
   AWS Frontier Agents - Interactions
   ============================================================ */

const FEEDBACK_URL = 'https://forms.cloud.microsoft/e/fRmVmmUGsF?origin=lprLink';

/* --- Stat Counters (S1.3) --- */
function initStatCounters() {
  const statEls = document.querySelectorAll('.slide-why-now .stat-number');
  let animated = false;

  Reveal.on('slidechanged', (event) => {
    const slide = event.currentSlide;
    if (!slide.classList.contains('slide-why-now')) return;

    if (animated) {
      statEls.forEach(el => {
        el.textContent = el.dataset.counterMode === 'text' ? '-' : '0';
        const bar = el.closest('.stat-counter').querySelector('.stat-bar-fill');
        if (bar) bar.style.width = '0%';
      });
    }

    animated = true;
    statEls.forEach((el, i) => {
      const bar = el.closest('.stat-counter').querySelector('.stat-bar-fill');

      setTimeout(() => {
        if (el.dataset.counterMode === 'text') {
          // Text reveal (non-numeric stats)
          el.innerHTML = el.dataset.counterText;
        } else {
          // Numeric counter
          const target = parseInt(el.dataset.counterTarget, 10);
          const suffix = el.dataset.counterSuffix || '';
          animateCounter(el, target, suffix, 1800);
        }
        if (bar) bar.style.width = '100%';
      }, i * 200);
    });
  });
}

function animateCounter(el, target, suffix, duration) {
  const start = performance.now();
  function tick(now) {
    const t = Math.min((now - start) / duration, 1);
    const eased = t * (2 - t); // ease-out quad
    const value = Math.round(eased * target);
    el.textContent = value + suffix;
    if (t < 1) requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
}

/* --- Agent Loop Animation (removed - slide no longer exists) --- */
function initAgentLoopAnim() {}

/* --- Trio Toggle Panels (S3.1) --- */
function initTrioToggle() {
  const cards = document.querySelectorAll('.trio-card');

  function toggleCard(card) {
    const wasExpanded = card.classList.contains('is-expanded');
    cards.forEach(c => c.classList.remove('is-expanded'));
    if (!wasExpanded) card.classList.add('is-expanded');
  }

  cards.forEach(card => {
    card.setAttribute('tabindex', '0');
    card.style.cursor = 'pointer';

    card.addEventListener('click', () => toggleCard(card));
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        toggleCard(card);
      }
    });
  });
}

/* --- Terminal Mock (S5.2, S5.3) --- */
function initTerminalMocks() {
  const terminalSlides = document.querySelectorAll('[data-terminal]');

  terminalSlides.forEach(slide => {
    const terminalBody = slide.querySelector('.terminal-body');
    const lines = JSON.parse(slide.dataset.terminal);
    let handle = null;

    function reset() {
      if (handle) { clearTimeout(handle); handle = null; }
      terminalBody.innerHTML = '<span class="terminal-cursor"></span>';
    }

    function play() {
      reset();
      let totalDelay = 0;

      lines.forEach((line, idx) => {
        totalDelay += line.delay || 0;

        handle = setTimeout(() => {
          const cursor = terminalBody.querySelector('.terminal-cursor');
          const lineEl = document.createElement('div');
          lineEl.classList.add('terminal-line', line.type);

          if (line.type === 'cmd') {
            typeText(lineEl, line.text, 28, cursor);
          } else {
            lineEl.textContent = line.text;
            terminalBody.insertBefore(lineEl, cursor);
          }
        }, totalDelay);

        if (line.type === 'cmd') {
          totalDelay += line.text.length * 28 + 200;
        }
      });
    }

    Reveal.on('slidechanged', (event) => {
      if (event.currentSlide === slide) {
        play();
      } else {
        reset();
      }
    });
  });
}

function typeText(container, text, charDelay, cursorEl) {
  let i = 0;
  const parent = cursorEl.parentNode;

  // Insert line container before cursor
  parent.insertBefore(container, cursorEl);

  function tick() {
    if (i < text.length) {
      // Handle prompt
      if (i === 0 && text.startsWith('$ ')) {
        const prompt = document.createElement('span');
        prompt.className = 'prompt';
        prompt.textContent = '$ ';
        container.appendChild(prompt);
        i = 2;
      } else {
        container.appendChild(document.createTextNode(text[i]));
        i++;
      }
      setTimeout(tick, charDelay);
    }
  }
  tick();
}

/* --- QR Code (S6.1) --- */
function initQRCode() {
  const canvas = document.getElementById('qr-canvas');
  if (!canvas || typeof QRCode === 'undefined') return;

  new QRCode(canvas, {
    text: FEEDBACK_URL,
    width: 256,
    height: 256,
    colorDark: '#00D4FF',
    colorLight: '#07080C',
    correctLevel: QRCode.CorrectLevel.H
  });
}

/* --- Init on Reveal ready --- */
Reveal.on('ready', () => {
  initStatCounters();
  initAgentLoopAnim();
  initTrioToggle();
  initTerminalMocks();
  initQRCode();
});
