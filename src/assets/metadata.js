(() => {
  if (typeof globalThis.__neteaseCollectNowPlaying === 'function') {
    return JSON.stringify(globalThis.__neteaseCollectNowPlaying());
  }

  function clean(text) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }

  const metadata = globalThis.__neteaseNowPlaying || {};
  const session = (navigator.mediaSession && navigator.mediaSession.metadata) || {};
  const title = clean(metadata.title || session.title || document.title || '').replace(/ - 网易云音乐.*$/, '');
  const media = globalThis.__neteaseActiveMedia || Array.from(document.querySelectorAll('audio, video')).find((m) => !m.paused) || null;
  return JSON.stringify({
    title,
    artist: clean(metadata.artist || session.artist || ''),
    album: clean(metadata.album || session.album || ''),
    artwork: metadata.artwork || (session.artwork && session.artwork[0] && session.artwork[0].src) || '',
    playing: !!(media && !media.paused),
    liked: !!metadata.liked,
    repeatMode: clean(metadata.repeatMode || '')
  });
})()
