import { useEvent, useEventListener } from "expo";
import { useVideoPlayer, VideoView } from "expo-video";
import { useContext, useEffect, useRef } from "react";
import {
  Animated,
  AppState,
  StyleSheet,
  View,
  Text,
  ActivityIndicator,
} from "react-native";
import { ThemeContext } from "../../../contexts/SettingsContexts/ThemeContext";
import { MediaViewerContext } from "../../../contexts/MediaViewerContext";
import DismountWhenBackgrounded from "../../Other/DismountWhenBackgrounded";
import VideoCache from "../../../utils/VideoCache";
import VideoPlaybackPositions from "../../../utils/VideoPlaybackPositions";

type VideoProps = {
  uri: string;
};

function Video({ uri }: VideoProps) {
  const { theme } = useContext(ThemeContext);
  const { subscribeToVisibility } = useContext(MediaViewerContext);
  const progress = useRef(new Animated.Value(0)).current;

  const player = useVideoPlayer(
    VideoCache.makeCachedVideoSource(uri),
    (player) => {
      player.audioMixingMode = "mixWithOthers";
      player.muted = true;
      player.loop = true;
      player.timeUpdateEventInterval = 1 / 15;
      player.bufferOptions = {
        maxBufferBytes: 1024 * 1024 * 5, // 5MB - Android only setting (prevents crashes)
      };
      /**
       * Intentionally starts from the beginning. Videos in the feed restart
       * whenever they're remounted, such as after scrolling off screen.
       */
      player.play();
    },
  );

  const status = useEvent(player, "statusChange");

  const isMediaViewerShowing = useRef(false);

  useEventListener(player, "timeUpdate", (e) => {
    progress.setValue(e.currentTime / player.duration);
    /**
     * While the media viewer is open it owns the playback position, so a
     * player back in the feed shouldn't overwrite it.
     */
    if (!isMediaViewerShowing.current) {
      VideoPlaybackPositions.save(uri, e.currentTime);
    }
  });

  useEffect(() => {
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active" && player.status === "readyToPlay") {
        player.play();
      }
    });
    return () => subscription.remove();
  }, [player]);

  useEffect(() => {
    return subscribeToVisibility((isShowing) => {
      isMediaViewerShowing.current = isShowing;
      if (isShowing) {
        player.pause();
      } else {
        /**
         * The media viewer may have moved this video forward while it was open,
         * so pick up wherever it left off instead of where we paused.
         */
        const savedPosition = VideoPlaybackPositions.get(uri);
        if (savedPosition) {
          player.currentTime = savedPosition;
        }
        player.play();
      }
    });
  }, [player, subscribeToVisibility, uri]);

  return (
    <View style={styles.videoContainer} pointerEvents="none">
      {status?.error ? (
        <View style={styles.notReadyContainer}>
          <Text style={styles.errorText}>{status.error.message}</Text>
        </View>
      ) : status === null || status.status === "loading" ? (
        <View style={styles.notReadyContainer}>
          <ActivityIndicator color={theme.text} />
        </View>
      ) : null}
      <VideoView
        player={player}
        style={styles.video}
        contentFit="contain"
        nativeControls={false}
        allowsVideoFrameAnalysis={false}
      />
      <View
        style={[
          styles.progressBarBackground,
          { backgroundColor: theme.background },
        ]}
      />
      <Animated.View
        style={[
          styles.progressBar,
          {
            backgroundColor: theme.subtleText,
            transform: [
              {
                scaleX: progress,
              },
            ],
          },
        ]}
      />
    </View>
  );
}

export default function VideoPlayerWrapper(props: VideoProps) {
  return (
    <DismountWhenBackgrounded>
      <Video {...props} />
    </DismountWhenBackgrounded>
  );
}

const styles = StyleSheet.create({
  videoContainer: {
    width: "100%",
    flex: 1,
    position: "relative",
    overflow: "hidden",
  },
  notReadyContainer: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "black",
    zIndex: 1,
  },
  errorText: {
    color: "white",
    textAlign: "center",
    margin: 10,
  },
  video: {
    width: "100%",
    flex: 1,
  },
  progressBarBackground: {
    position: "absolute",
    bottom: 0,
    width: "100%",
    height: 2,
    backgroundColor: "black",
  },
  progressBar: {
    position: "absolute",
    bottom: 0,
    width: "200%",
    left: "-100%",
    height: 2,
  },
});
