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
      repeatMode: metadata.repeatMode || '',
      muted: !!metadata.muted
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

  function miniBarRoot() {
    return document.querySelector('#page_pc_mini_bar');
  }

  function playerControlsRoot() {
    return document.querySelector('#page_pc_mini_bar .middle .btns');
  }

  function hasMiniBar() {
    return !!document.querySelector('#page_pc_mini_bar');
  }

  function controlsRoot() {
    return miniBarRoot() || document;
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

  function findLikeControl() {
    const root = playerControlsRoot();
    if (!root) return null;
    const icon = root.querySelector('.cmd-icon-like[aria-label="like"][title="喜欢"], .cmd-icon-like[aria-label="like"][title="取消喜欢"]');
    if (!icon || !visibleNode(icon)) return null;
    const button = icon.closest('button');
    if (!button || !visibleNode(button)) return null;
    return { node: button, icon, label: controlLabel(button) + ' ' + controlLabel(icon), title: icon.getAttribute('title') || '' };
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

  function activeLikeState(found) {
    if (!found) return false;
    return found.title === '取消喜欢';
  }

  function findRepeatControl() {
    const root = playerControlsRoot();
    if (!root) return null;
    const icon = root.querySelector('.cmd-icon[title="随机播放"], .cmd-icon[title="顺序播放"], .cmd-icon[title="心动模式"], .cmd-icon[title="列表循环"], .cmd-icon[title="单曲循环"]');
    if (!icon || !visibleNode(icon)) return null;
    const button = icon.closest('button');
    if (!button || !visibleNode(button)) return null;
    return { node: button, icon, title: icon.getAttribute('title') || '' };
  }

  function readRepeatMode(found) {
    if (!found) return '';
    return found.title;
  }

  function findMuteControl() {
    const root = miniBarRoot();
    if (!root) return null;
    const icon = root.querySelector('.right-side .cmd-icon-volume[aria-label="volume"][title="静音"], .right-side .cmd-icon-mute[aria-label="mute"][title="解除静音"]');
    if (!icon) return null;
    const button = icon.closest('button');
    if (!button) return null;
    return { node: button, icon, title: icon.getAttribute('title') || '' };
  }

  function activeMutedState(found) {
    return !!found && found.title === '解除静音';
  }

  function collectNowPlayingFromThisFrame() {
    const meta = globalThis.__neteaseNowPlaying || (navigator.mediaSession && navigator.mediaSession.metadata) || {};
    const play = document.querySelector('#page_pc_mini_bar #btn_pc_minibar_play');
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
    const likeControl = findLikeControl();
    const repeatControl = findRepeatControl();
    const muteControl = findMuteControl();
    const liked = activeLikeState(likeControl);
    const repeatMode = readRepeatMode(repeatControl);
    const muted = activeMutedState(muteControl);

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

    return { title, artist, album, artwork, playing, liked, repeatMode, muted };
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
    document.addEventListener('volumechange', publishNowPlaying, true);
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
    const controls = playerControlsRoot();
    const play = controls && controls.querySelector('#btn_pc_minibar_play');
    if (!play) return null;
    const buttons = Array.from(controls.querySelectorAll('button'));
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
    const button = document.querySelector('#page_pc_mini_bar #btn_pc_minibar_play');
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
    const button = document.querySelector('#page_pc_mini_bar #btn_pc_minibar_play');
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
    const found = findControl(patterns, playerControlsRoot());
    if (!found) return false;
    found.node.click();
    setTimeout(publishNowPlaying, 150);
    return true;
  }

  const repeatOrder = ['随机播放', '顺序播放', '心动模式', '列表循环', '单曲循环'];

  function cycleRepeatButton() {
    const found = findRepeatControl();
    if (!found) return false;
    found.node.click();
    refreshSoon();
    return true;
  }

  function setRepeatMode(target) {
    if (!repeatOrder.includes(target)) return false;
    const found = findRepeatControl();
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

  function dispatchControlClick(node) {
    if (!node) return;
    if (globalThis.PointerEvent) {
      node.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true, view: window, pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: 1, button: 0 }));
    } else {
      node.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, cancelable: true, view: window, buttons: 1, button: 0 }));
    }
    node.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window, buttons: 1, button: 0 }));
    if (globalThis.PointerEvent) {
      node.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, cancelable: true, view: window, pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: 0, button: 0 }));
    } else {
      node.dispatchEvent(new MouseEvent('pointerup', { bubbles: true, cancelable: true, view: window, buttons: 0, button: 0 }));
    }
    node.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window, buttons: 0, button: 0 }));
    node.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window, buttons: 0, button: 0 }));
  }

  function toggleMute() {
    const found = findMuteControl();
    if (!found) return false;
    dispatchControlClick(found.node);
    refreshSoon();
    return true;
  }


  globalThis.__neteaseTrayAction = function (action, value) {
    if (!hasMiniBar()) {
      return action === 'showWindow';
    }
    if (action === 'play') return playOnly();
    if (action === 'playPause') return playPause();
    if (action === 'previous') { const button = playerButton(-1); if (button) { button.click(); refreshSoon(); return true; } return false; }
    if (action === 'next') { const button = playerButton(1); if (button) { button.click(); refreshSoon(); return true; } return false; }
    if (action === 'toggleLike') {
      return clickLikeControl(findLikeControl());
    }
    if (action === 'setRepeatMode') return setRepeatMode(value);
    if (action === 'toggleMute') return toggleMute();
    return false;
  };

  document.addEventListener('keydown', function (event) {
    if (editableTarget(event.target)) return;

    let handled = false;
    if (event.key === ' ' || event.key === 'Spacebar') handled = playPause();
    else if (event.key === 'ArrowUp') {
      const button = playerButton(-1);
      if (button) { button.click(); handled = true; }
      else handled = false;
    }
    else if (event.key === 'ArrowDown') {
      const button = playerButton(1);
      if (button) { button.click(); handled = true; }
      else handled = false;
    }

    if (handled) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);
})();
