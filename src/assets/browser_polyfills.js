(() => {
  if (!globalThis.requestIdleCallback) {
    globalThis.requestIdleCallback = function (callback, options) {
      const start = Date.now();
      const timeout = options && typeof options.timeout === 'number' ? options.timeout : 1;
      return setTimeout(function () {
        callback({
          didTimeout: false,
          timeRemaining: function () { return Math.max(0, 50 - (Date.now() - start)); }
        });
      }, timeout);
    };
  }
  if (!globalThis.cancelIdleCallback) {
    globalThis.cancelIdleCallback = function (id) { clearTimeout(id); };
  }

  function editableTarget(target) {
    if (!target) return false;
    const tag = target.tagName;
    return target.isContentEditable || tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
  }

  if (!globalThis.__neteaseMediaPatched) {
    globalThis.__neteaseMediaPatched = true;
    const originalPlay = HTMLMediaElement.prototype.play;
    const originalPause = HTMLMediaElement.prototype.pause;
    HTMLMediaElement.prototype.play = function () {
      globalThis.__neteaseActiveMedia = this;
      return originalPlay.apply(this, arguments);
    };
    HTMLMediaElement.prototype.pause = function () {
      globalThis.__neteaseActiveMedia = this;
      return originalPause.apply(this, arguments);
    };
    document.addEventListener('play', function (event) {
      if (event.target instanceof HTMLMediaElement) globalThis.__neteaseActiveMedia = event.target;
    }, true);
  }

  function updateNowPlayingFromMetadata(metadata) {
    if (!metadata) return;
    const media = globalThis.__neteaseActiveMedia;
    globalThis.__neteaseNowPlaying = {
      title: metadata.title || '',
      artist: metadata.artist || '',
      album: metadata.album || '',
      artwork: metadata.artwork && metadata.artwork[0] && metadata.artwork[0].src || '',
      playing: !!(media && !media.paused)
    };
  }

  if (!globalThis.__neteaseMediaSessionPatched) {
    globalThis.__neteaseMediaSessionPatched = true;
    const OriginalMediaMetadata = globalThis.MediaMetadata;
    if (OriginalMediaMetadata) {
      globalThis.MediaMetadata = function (init) {
        const metadata = new OriginalMediaMetadata(init);
        updateNowPlayingFromMetadata(metadata);
        return metadata;
      };
      globalThis.MediaMetadata.prototype = OriginalMediaMetadata.prototype;
    }
    if (navigator.mediaSession) {
      const proto = Object.getPrototypeOf(navigator.mediaSession);
      const desc = Object.getOwnPropertyDescriptor(proto, 'metadata');
      if (desc && desc.set && desc.get) {
        Object.defineProperty(proto, 'metadata', {
          get: desc.get,
          set: function (value) {
            desc.set.call(this, value);
            updateNowPlayingFromMetadata(value);
          }
        });
        updateNowPlayingFromMetadata(navigator.mediaSession.metadata);
      }
    }
  }

  globalThis.__neteaseGetNowPlaying = function () {
    const metadata = globalThis.__neteaseNowPlaying || {};
    const title = metadata.title || document.title || '';
    const media = currentMedia();
    return JSON.stringify({
      title: title,
      artist: metadata.artist || '',
      album: metadata.album || '',
      artwork: metadata.artwork || '',
      playing: !!(media && !media.paused),
      liked: !!metadata.liked,
      repeatMode: metadata.repeatMode || ''
    });
  };

  function cleanText(text) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }

  function visibleNode(node) {
    if (!node || !node.getBoundingClientRect) return false;
    const rect = node.getBoundingClientRect();
    const style = getComputedStyle(node);
    return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
  }

  function playerControlsRoot() {
    const play = document.querySelector('#btn_pc_minibar_play');
    if (!play) return null;
    return play.closest('footer, .page-footer, .cmd-space, [class*=footer], [class*=bar]') || play.parentElement;
  }

  function controlsRoot() {
    return playerControlsRoot() || document;
  }

  function controlNodes(root) {
    return Array.from((root || document).querySelectorAll('button, [role="button"], a, [title], [aria-label]')).filter(visibleNode);
  }

  function controlLabel(node) {
    return [
      node.getAttribute && node.getAttribute('aria-label'),
      node.getAttribute && node.getAttribute('title'),
      node.textContent,
      node.className && String(node.className),
    ].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
  }

  function findControl(patterns, root) {
    for (const node of controlNodes(root)) {
      const label = controlLabel(node);
      if (patterns.some((p) => p.test(label))) return { node, label };
    }
    return null;
  }

  function findLikeControl(root) {
    if (!root) return null;
    const play = document.querySelector('#btn_pc_minibar_play');
    const playRect = play && play.getBoundingClientRect && play.getBoundingClientRect();
    const selectors = '.cmd-icon-like, .cmd-icon[aria-label="like"], .cmd-icon[title="喜欢"], .cmd-icon[title="取消喜欢"]';
    const candidates = [];

    for (const icon of Array.from(root.querySelectorAll(selectors)).filter(visibleNode)) {
      const button = icon.closest('button, [role="button"]') || icon;
      if (button.closest('#page_pc_main_nav, nav, aside')) continue;
      const rect = icon.getBoundingClientRect();
      const dist = playRect ? Math.hypot(rect.left - playRect.left, rect.top - playRect.top) : 0;
      const looksMiniBar = button.classList && (button.classList.contains('cmd-button-with-icon-only') || button.classList.contains('cmd-button-surfacePri'));
      candidates.push({
        node: button,
        icon,
        label: controlLabel(button) + ' ' + controlLabel(icon),
        title: icon.getAttribute('title') || '',
        dist,
        looksMiniBar,
      });
    }

    candidates.sort((a, b) => {
      // State title is not a selector priority: an old/offscreen/other like
      // button may also say "取消喜欢". The current-song button is the mini-bar
      // heart closest to #btn_pc_minibar_play.
      if (a.looksMiniBar !== b.looksMiniBar) return a.looksMiniBar ? -1 : 1;
      return a.dist - b.dist;
    });
    return candidates[0] || null;
  }

  function findLikeControlAnywhere() {
    return findLikeControl(playerControlsRoot()) || findLikeControl(document);
  }


  function clickLikeControl(found) {
    if (!found) return false;
    const nextLiked = !activeLikeState(found);
    const targets = [found.icon, found.node].filter(Boolean);
    for (const target of targets) {
      for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
        target.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
      }
    }
    const info = collectNowPlayingFromThisFrame();
    info.liked = nextLiked;
    sendNowPlaying(info);
    refreshSoon();
    return true;
  }

  function isRedLikeColor(value) {
    const m = String(value || '').match(/rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/i);
    if (!m) return false;
    const r = Number(m[1]), g = Number(m[2]), b = Number(m[3]);
    return r >= 160 && g <= 120 && b <= 140;
  }

  function activeLikeState(found) {
    if (!found) return false;
    const icon = found.icon || found.node;
    const label = found.label;
    const title = icon.getAttribute('title') || '';

    // For NetEase mini-bar this is the most reliable state marker:
    // unliked => title="喜欢", liked => title="取消喜欢".
    if (title === '取消喜欢') return true;
    if (title === '喜欢') return false;

    if (/已喜欢|unlike|liked/i.test(label)) return true;
    if (/添加喜欢|未喜欢/i.test(label)) return false;

    const iconStyle = getComputedStyle(icon);
    const buttonStyle = getComputedStyle(found.node);
    if (isRedLikeColor(iconStyle.color) || isRedLikeColor(iconStyle.fill) || isRedLikeColor(buttonStyle.color)) return true;

    const attrs = [
      icon.getAttribute('aria-pressed'),
      icon.getAttribute('aria-selected'),
      icon.getAttribute('data-checked'),
      icon.getAttribute('data-liked'),
      found.node.getAttribute('aria-pressed'),
      found.node.getAttribute('aria-selected'),
      found.node.getAttribute('data-checked'),
      found.node.getAttribute('data-liked'),
    ].filter(Boolean).join(' ');
    if (/true|1|yes/i.test(attrs)) return true;
    if (/false|0|no/i.test(attrs)) return false;

    const klass = String(icon.className || '') + ' ' + String(found.node.className || '');
    if (/liked|like-fill|likeFill|filled|active|checked|selected|z-sel|is-?liked|on/i.test(klass)) return true;

    // The mini bar like icon is an SVG.  In the unliked state the root SVG from
    // NetEase is `fill="none"`; the liked state is rendered as a filled heart
    // by setting fill on the svg/path/use.  Inspect descendants instead of the
    // wrapper label, otherwise `aria-label="like"` would always look unliked.
    const svg = icon.querySelector && icon.querySelector('svg');
    if (svg) {
      const rootFill = svg.getAttribute('fill');
      const filledChild = Array.from(svg.querySelectorAll('path, use, polygon, circle')).some((child) => {
        const attrFill = child.getAttribute('fill');
        const attrClass = String(child.getAttribute('class') || '');
        if (attrFill && attrFill !== 'none' && attrFill !== 'transparent') return true;
        if (/fill|filled|active|liked/i.test(attrClass)) return true;
        const childStyle = getComputedStyle(child);
        const styleFill = childStyle.fill;
        return isRedLikeColor(styleFill) || isRedLikeColor(childStyle.color);
      });
      if (filledChild) return true;
      if (rootFill && rootFill !== 'none' && rootFill !== 'transparent') return true;
      return false;
    }

    return false;
  }

  function findRepeatControlAnywhere() {
    const selectors = [
      '.cmd-icon-singleloop',
      '.cmd-icon-listloop',
      '.cmd-icon-orderplay',
      '.cmd-icon-randomplay',
      '.cmd-icon-shuffle',
      '.cmd-icon-heartmode',
      '.cmd-icon[aria-label*="loop" i]',
      '.cmd-icon[aria-label*="random" i]',
      '.cmd-icon[aria-label*="shuffle" i]',
      '.cmd-icon[title*="循环"]',
      '.cmd-icon[title*="随机"]',
      '.cmd-icon[title*="顺序"]',
      '.cmd-icon[title*="心动"]',
    ].join(',');

    const play = document.querySelector('#btn_pc_minibar_play');
    const playRect = play && play.getBoundingClientRect && play.getBoundingClientRect();
    const candidates = [];
    for (const icon of Array.from(document.querySelectorAll(selectors)).filter(visibleNode)) {
      const button = icon.closest('button, [role="button"]') || icon;
      if (button.closest('#page_pc_main_nav, nav, aside')) continue;
      const rect = icon.getBoundingClientRect();
      candidates.push({
        node: button,
        icon,
        label: controlLabel(button) + ' ' + controlLabel(icon),
        title: icon.getAttribute('title') || '',
        ariaLabel: icon.getAttribute('aria-label') || '',
        className: String(icon.className || ''),
        distanceToPlay: playRect ? Math.hypot(rect.left - playRect.left, rect.top - playRect.top) : 0,
      });
    }
    candidates.sort((a, b) => a.distanceToPlay - b.distanceToPlay);
    return candidates[0] || null;
  }

  function readRepeatMode(found) {
    if (!found) return '';
    const label = [found.title, found.ariaLabel, found.className, found.label].join(' ');
    if (/心动/i.test(label)) return '心动模式';
    if (/单曲|singleloop|single|one/i.test(label)) return '单曲循环';
    if (/随机|random|shuffle/i.test(label)) return '随机播放';
    if (/顺序|order|sequence/i.test(label)) return '顺序播放';
    if (/列表|listloop|循环|repeat|loop/i.test(label)) return '列表循环';
    return '';
  }

  function collectNowPlayingFromThisFrame() {
    const meta = globalThis.__neteaseNowPlaying || (navigator.mediaSession && navigator.mediaSession.metadata) || {};
    const play = document.querySelector('#btn_pc_minibar_play');
    const root = controlsRoot();
    function textOf(selector) {
      const node = root.querySelector(selector);
      return node && visibleNode(node) ? cleanText(node.textContent || node.getAttribute('title') || node.getAttribute('aria-label')) : '';
    }
    function attrOf(selector, attr) {
      const node = root.querySelector(selector);
      return node && visibleNode(node) ? cleanText(node.getAttribute(attr)) : '';
    }
    let title = cleanText(meta.title) || textOf('a[href*="/song"], [class*="song"], [class*="name"], [class*="title"]') || attrOf('[title]', 'title');
    let artist = cleanText(meta.artist) || textOf('a[href*="/artist"], [class*="artist"], [class*="author"], [class*="singer"]');
    const album = cleanText(meta.album);
    const artwork = (meta.artwork && meta.artwork[0] && meta.artwork[0].src) || attrOf('img[src]', 'src');
    const media = currentMedia();
    const playing = !!(media && !media.paused);
    const likeControl = findLikeControlAnywhere();
    const repeatControl = findRepeatControlAnywhere();
    const liked = activeLikeState(likeControl);
    const repeatMode = readRepeatMode(repeatControl);

    if (!title && play) {
      const bad = /播放|暂停|上一|下一|喜欢|收藏|列表|歌词|音量|循环|随机|prev|next|play|pause|volume/i;
      const texts = [];
      for (const node of Array.from(root.querySelectorAll('a, span, div, p')).filter(visibleNode)) {
        const t = cleanText(node.textContent || node.getAttribute('title') || '');
        if (t.length >= 1 && t.length <= 80 && !bad.test(t) && !texts.includes(t)) texts.push(t);
        if (texts.length >= 2) break;
      }
      title = texts[0] || '';
      artist = artist || texts[1] || '';
    }

    return { title, artist, album, artwork, playing, liked, repeatMode };
  }

  function sendNowPlaying(info) {
    globalThis.__neteaseNowPlaying = info;
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.neteaseNowPlaying) {
        window.webkit.messageHandlers.neteaseNowPlaying.postMessage(JSON.stringify(info));
      }
    } catch (_) {}
    try {
      if (window.top && window.top !== window) window.top.postMessage({ __neteaseNowPlaying: info }, '*');
    } catch (_) {}
  }

  globalThis.__neteaseCollectNowPlaying = collectNowPlayingFromThisFrame;

  function publishNowPlaying() {
    const info = collectNowPlayingFromThisFrame();
    if (!info.title && !info.artist && !info.artwork) return;
    sendNowPlaying(info);
  }

  globalThis.__neteasePublishNowPlaying = publishNowPlaying;

  if (!globalThis.__neteaseNowPlayingPublisher) {
    globalThis.__neteaseNowPlayingPublisher = true;
    window.addEventListener('message', function (event) {
      if (event && event.data && event.data.__neteaseNowPlaying) {
        globalThis.__neteaseNowPlaying = event.data.__neteaseNowPlaying;
      }
    });
    setInterval(publishNowPlaying, 1000);
    document.addEventListener('play', publishNowPlaying, true);
    document.addEventListener('pause', publishNowPlaying, true);
    document.addEventListener('click', function () { setTimeout(publishNowPlaying, 100); }, true);
    let mutationTimer = 0;
    new MutationObserver(function () {
      clearTimeout(mutationTimer);
      mutationTimer = setTimeout(publishNowPlaying, 150);
    }).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'title', 'aria-label', 'aria-pressed', 'aria-selected', 'data-checked', 'data-liked'] });
    publishNowPlaying();
  }

  function currentMedia() {
    if (globalThis.__neteaseActiveMedia) return globalThis.__neteaseActiveMedia;
    const media = Array.from(document.querySelectorAll('audio, video'));
    return media.find((m) => !m.paused) || media[0] || null;
  }

  function playerButton(offset) {
    const play = document.querySelector('#btn_pc_minibar_play');
    if (!play) return null;
    const controls = play.closest('.cmd-space, footer, .page-footer') || play.parentElement;
    if (!controls) return null;
    const buttons = Array.from(controls.querySelectorAll('button, [role="button"], a'));
    const index = buttons.indexOf(play);
    if (index < 0) return null;
    return buttons[index + offset] || null;
  }

  function refreshSoon() {
    setTimeout(publishNowPlaying, 150);
    setTimeout(publishNowPlaying, 600);
    setTimeout(publishNowPlaying, 1200);
  }

  function playOnly() {
    const media = currentMedia();
    if (media && !media.paused) return true;
    const button = document.querySelector('#btn_pc_minibar_play');
    if (button) {
      button.click();
      refreshSoon();
      return true;
    }
    if (!media) return false;
    media.play().catch(() => {});
    refreshSoon();
    return true;
  }

  function playPause() {
    const button = document.querySelector('#btn_pc_minibar_play');
    if (button) {
      button.click();
      refreshSoon();
      return true;
    }
    const media = currentMedia();
    if (!media) return false;
    if (media.paused) media.play().catch(() => {});
    else media.pause();
    return true;
  }

  function clickControl(patterns) {
    const found = findControl(patterns, controlsRoot()) || findControl(patterns, document);
    if (!found) return false;
    found.node.click();
    setTimeout(publishNowPlaying, 150);
    return true;
  }

  const repeatOrder = ['随机播放', '顺序播放', '心动模式', '列表循环', '单曲循环'];

  function cycleRepeatButton() {
    const found = findRepeatControlAnywhere();
    if (!found) return false;
    found.node.click();
    refreshSoon();
    return true;
  }

  function setRepeatMode(target) {
    if (!repeatOrder.includes(target)) return false;
    const found = findRepeatControlAnywhere();
    const current = readRepeatMode(found);
    const from = repeatOrder.indexOf(current);
    const to = repeatOrder.indexOf(target);
    if (from < 0 || to < 0) return false;
    const steps = (to - from + repeatOrder.length) % repeatOrder.length;
    for (let i = 0; i < steps; i++) {
      setTimeout(cycleRepeatButton, i * 120);
    }
    setTimeout(publishNowPlaying, steps * 120 + 200);
    setTimeout(publishNowPlaying, steps * 120 + 700);
    return true;
  }

  // Some web apps disable the browser context menu. Stop their handlers
  // from seeing right-click, but do not prevent the browser/WebKit default.
  document.addEventListener('contextmenu', function (event) {
    event.stopImmediatePropagation();
  }, true);

  globalThis.__neteaseTrayAction = function (action, value) {
    if (action === 'play') return playOnly();
    if (action === 'playPause') return playPause();
    if (action === 'previous') { const button = playerButton(-1); if (button) { button.click(); refreshSoon(); return true; } return clickControl([/上一/, /prev/i, /previous/i]); }
    if (action === 'next') { const button = playerButton(1); if (button) { button.click(); refreshSoon(); return true; } return clickControl([/下一/, /next/i]); }
    if (action === 'toggleLike') {
      return clickLikeControl(findLikeControlAnywhere());
    }
    if (action === 'setRepeatMode') return setRepeatMode(value);
    return false;
  };

  document.addEventListener('keydown', function (event) {
    if (editableTarget(event.target)) return;

    let handled = false;
    if (event.key === ' ' || event.key === 'Spacebar') handled = playPause();
    else if (event.key === 'ArrowUp') {
      const button = playerButton(-1);
      if (button) { button.click(); handled = true; }
      else handled = clickControl([/上一/, /prev/i, /previous/i]);
    }
    else if (event.key === 'ArrowDown') {
      const button = playerButton(1);
      if (button) { button.click(); handled = true; }
      else handled = clickControl([/下一/, /next/i]);
    }

    if (handled) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);
})();
