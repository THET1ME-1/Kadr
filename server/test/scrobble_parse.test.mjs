// Тест чистого парсера вебхуков скробблинга. Запуск: node --test server/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseScrobble } from '../src/index.js';

test('Plex: эпизод (media.scrobble)', () => {
  const r = parseScrobble({
    event: 'media.scrobble',
    Metadata: { type: 'episode', grandparentTitle: 'Severance', parentIndex: 2, index: 5 },
  });
  assert.deepEqual(r, { kind: 'episode', title: 'Severance', year: null, season: 2, episode: 5, source: 'plex' });
});

test('Plex: фильм', () => {
  const r = parseScrobble({ event: 'media.scrobble', Metadata: { type: 'movie', title: 'Dune', year: 2021 } });
  assert.deepEqual(r, { kind: 'movie', title: 'Dune', year: 2021, season: null, episode: null, source: 'plex' });
});

test('Plex: не-скроббл событие (media.play) → null', () => {
  assert.equal(parseScrobble({ event: 'media.play', Metadata: { type: 'movie', title: 'Dune' } }), null);
});

test('Jellyfin: эпизод (PlaybackStop, досмотрен)', () => {
  const r = parseScrobble({
    NotificationType: 'PlaybackStop',
    ItemType: 'Episode',
    SeriesName: 'Dark',
    SeasonNumber: 1,
    EpisodeNumber: 2,
    PlayedToCompletion: true,
  });
  assert.deepEqual(r, { kind: 'episode', title: 'Dark', year: null, season: 1, episode: 2, source: 'jellyfin' });
});

test('Jellyfin: фильм (MarkPlayed)', () => {
  const r = parseScrobble({ NotificationType: 'MarkPlayed', ItemType: 'Movie', Name: 'Inception', Year: 2010 });
  assert.deepEqual(r, { kind: 'movie', title: 'Inception', year: 2010, season: null, episode: null, source: 'jellyfin' });
});

test('Jellyfin: PlaybackStop без досмотра → null', () => {
  assert.equal(
    parseScrobble({ NotificationType: 'PlaybackStop', ItemType: 'Episode', SeriesName: 'Dark', PlayedToCompletion: false }),
    null,
  );
});

test('Jellyfin: строковые числа парсятся', () => {
  const r = parseScrobble({
    NotificationType: 'PlaybackStop',
    ItemType: 'Episode',
    SeriesName: 'Ben 10',
    SeasonNumber: '3',
    EpisodeNumber: '1',
    PlayedToCompletion: 'true',
  });
  assert.deepEqual(r, { kind: 'episode', title: 'Ben 10', year: null, season: 3, episode: 1, source: 'jellyfin' });
});

test('мусор → null', () => {
  assert.equal(parseScrobble(null), null);
  assert.equal(parseScrobble({}), null);
  assert.equal(parseScrobble({ foo: 'bar' }), null);
});
