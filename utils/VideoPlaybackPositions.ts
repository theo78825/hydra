const MAX_TRACKED_VIDEOS = 100;

const positions = new Map<string, number>();

/**
 * Remembers where each video was last playing, keyed by source uri, so playback
 * can be handed off between the inline player and the fullscreen media viewer.
 * Also covers the fullscreen player remounting when the device is rotated.
 *
 * Positions only live for the current app session.
 */
export default class VideoPlaybackPositions {
  static set(uri: string, position: number): void {
    /**
     * Deleting first keeps the Map's insertion order accurate so the entry we
     * evict below is always the least recently played one.
     */
    positions.delete(uri);
    positions.set(uri, position);
    if (positions.size > MAX_TRACKED_VIDEOS) {
      const oldest = positions.keys().next();
      if (!oldest.done) {
        positions.delete(oldest.value);
      }
    }
  }

  static get(uri: string): number | undefined {
    return positions.get(uri);
  }
}
