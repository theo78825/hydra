/**
 * Keeps track of where each video was last played so that playback can be
 * picked back up from the same spot when the video is shown somewhere else
 * (e.g. tapping a video in the feed to open it in the media viewer) or when
 * the player is remounted (e.g. rotating the phone).
 */

const MAX_TRACKED_VIDEOS = 100;

export default class VideoPlaybackPositions {
  private static positions = new Map<string, number>();

  static save(uri: string, position: number): void {
    if (!uri || !isFinite(position) || position <= 0) return;
    /**
     * Deleting before setting moves the entry to the end of the map so that
     * the least recently played videos are the ones that get evicted.
     */
    this.positions.delete(uri);
    this.positions.set(uri, position);
    if (this.positions.size > MAX_TRACKED_VIDEOS) {
      const oldestUri = this.positions.keys().next().value;
      if (oldestUri !== undefined) {
        this.positions.delete(oldestUri);
      }
    }
  }

  static get(uri: string): number {
    return this.positions.get(uri) ?? 0;
  }

  static clear(): void {
    this.positions.clear();
  }
}
