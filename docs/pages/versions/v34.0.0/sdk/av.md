---
title: AV
sourceCodeUrl: "https://github.com/expo/expo/tree/sdk-34/packages/expo-av"
---

The [`Audio.Sound`](../audio/) objects and [`Video`](../video/) components share a unified imperative API for media playback.

Note that for `Video`, all of these operations are also available via props on the component, but we recommend using this imperative playback API for most applications where finer control over the state of the video playback is needed.

Try the [playlist example app](http://expo.io/@community/playlist) (source code is [on GitHub](https://github.com/expo/playlist-example)) to see an example usage of the playback API for both `Audio.Sound` and `Video`.

## Installation

For [managed](../../introduction/managed-vs-bare/#managed-workflow) apps, you'll need to run `expo install expo-av`. To use it in a [bare](../../introduction/managed-vs-bare/#bare-workflow) React Native app, follow its [installation instructions](https://github.com/expo/expo/tree/master/packages/expo-av).

## API

```js
import { Audio, Video } from 'expo-av';
```

## Usage

### Construction and obtaining a reference

In this page, we reference operations on `playbackObject`s. Here is an example of obtaining access to the reference for both sound and video:

#### Example: `Audio.Sound`

```javascript
const playbackObject = new Audio.Sound();
// OR
const playbackObject = await Audio.Sound.createAsync(
  { uri: 'http://foo/bar.mp3' },
  { shouldPlay: true }
);
...
```

See the [audio documentation](../audio/) for further information on `Audio.Sound.createAsync()`.

#### Example: `Video`

```javascript
...
_handleVideoRef = component => {
  const playbackObject = component;
  ...
}

...

render() {
  return (
    ...
      <Video
        ref={this._handleVideoRef}
        ...
      />
    ...
  )
}
...
```

## Playback API

On the `playbackObject` reference, the following API is provided:

- `playbackObject.loadAsync(source, initialStatus = {}, downloadFirst = true)`

  Loads the media from `source` into memory and prepares it for playing. This must be called before calling `setStatusAsync()` or any of the convenience set status methods. This method can only be called if the `playbackObject` is in an unloaded state.

  #### Parameters

  - **source (_object_ / _number_ / _Asset_)** -- The source of the media. The following forms are supported:

    - A dictionary of the form `{ uri: string, headers?: { [string]: string }, overrideFileExtensionAndroid?: string }` with a network URL pointing to a media file on the web, an optional headers object passed in a network request to the `uri` and an optional Android-specific `overrideFileExtensionAndroid` string overriding extension inferred from the URL.

      The `overrideFileExtensionAndroid` property may come in handy if the player receives an URL like `example.com/play` which redirects to `example.com/player.m3u8`. Setting this property to `m3u8` would allow the Android player to properly infer the content type of the media and use proper media file reader.

    - `require('path/to/file')` for a media file asset in the source code directory.
    - An [`Asset`](../asset/) object for a media file asset.

    The [iOS developer documentation](https://developer.apple.com/library/ios/documentation/Miscellaneous/Conceptual/iPhoneOSTechOverview/MediaLayer/MediaLayer.html) lists the audio and video formats supported on iOS.

    There are two sets of audio and video formats supported on Android: [formats supported by ExoPlayer](https://google.github.io/ExoPlayer/supported-formats.html) and [formats supported by Android's MediaPlayer](https://developer.android.com/guide/appendix/media-formats.html#formats-table). Expo uses ExoPlayer implementation by default; to use `MediaPlayer`, add `androidImplementation: 'MediaPlayer'` to the initial status of the AV object.

  - **initialStatus (_PlaybackStatusToSet_)** -- The initial intended `PlaybackStatusToSet` of the `playbackObject`, whose values will override the default initial playback status. This value defaults to `{}` if no parameter is passed. See below for details on `PlaybackStatusToSet` and the default initial playback status.

  - **downloadFirst (_boolean_)** -- If set to true, the system will attempt to download the resource to the device before loading. This value defaults to `true`. Note that at the moment, this will only work for `source`s of the form `require('path/to/file')` or `Asset` objects.

  #### Returns

  A `Promise` that is fulfilled with the `PlaybackStatus` of the `playbackObject` once it is loaded, or rejects if loading failed. The `Promise` will also reject if the `playbackObject` was already loaded. See below for details on `PlaybackStatus`.

- `playbackObject.unloadAsync()`

  Unloads the media from memory. `loadAsync()` must be called again in order to be able to play the media.

  #### Returns

  A `Promise` that is fulfilled with the `PlaybackStatus` of the `playbackObject` once it is unloaded, or rejects if unloading failed. See below for details on `PlaybackStatus`.

- `playbackObject.getStatusAsync()`

  Gets the `PlaybackStatus` of the `playbackObject`.

  #### Returns

  A `Promise` that is fulfilled with the `PlaybackStatus` of the `playbackObject`. See below for details on `PlaybackStatus`.

- `playbackObject.setOnPlaybackStatusUpdate(onPlaybackStatusUpdate)`

  Sets a function to be called regularly with the `PlaybackStatus` of the `playbackObject`. See below for details on `PlaybackStatus` and an example use case of this function.

  `onPlaybackStatusUpdate` will be called whenever a call to the API for this `playbackObject` completes (such as `setStatusAsync()`, `getStatusAsync()`, or `unloadAsync()`), and will also be called at regular intervals while the media is in the loaded state. Set `progressUpdateIntervalMillis` via `setStatusAsync()` or `setProgressUpdateIntervalAsync()` to modify the interval with which `onPlaybackStatusUpdate` is called while loaded.

  #### Parameters

  - **onPlaybackStatusUpdate (_function_)** -- A function taking a single parameter `PlaybackStatus` (a dictionary, described below).

- `playbackObject.replayAsync(statusToSet)`

  Replays the item. When using `playFromPositionAsync(0)` the item is seeked to the position at `0 ms`. On iOS this method uses internal implementation of the player and is able to play the item from the beginning immediately.

  #### Parameters

  - **statusToSet (_PlaybackStatusToSet_)** -- The new `PlaybackStatusToSet` of the `playbackObject`, whose values will override the current playback status. See below for details on `PlaybackStatusToSet`. `positionMillis` and `shouldPlay` properties will be overriden with respectively `0` and `true`.

  #### Returns

  A `Promise` that is fulfilled with the `PlaybackStatus` of the `playbackObject` once the new status has been set successfully, or rejects if setting the new status failed. See below for details on `PlaybackStatus`.

- `playbackObject.setStatusAsync(statusToSet)`

  Sets a new `PlaybackStatusToSet` on the `playbackObject`. This method can only be called if the media has been loaded.

  #### Parameters

  - **statusToSet (_PlaybackStatusToSet_)** -- The new `PlaybackStatusToSet` of the `playbackObject`, whose values will override the current playback status. See below for details on `PlaybackStatusToSet`.

  #### Returns

  A `Promise` that is fulfilled with the `PlaybackStatus` of the `playbackObject` once the new status has been set successfully, or rejects if setting the new status failed. See below for details on `PlaybackStatus`.

The following convenience methods built on top of `setStatusAsync()` are also provided. Each has the same return value as `setStatusAsync()`.

- `playbackObject.playAsync()`

  This is equivalent to `playbackObject.setStatusAsync({ shouldPlay: true })`.

  Playback may not start immediately after calling this function for reasons such as buffering. Make sure to update your UI based on the `isPlaying` and `isBuffering` properties of the `PlaybackStatus` (described below).

- `playbackObject.playFromPositionAsync(millis)`

  This is equivalent to `playbackObject.setStatusAsync({ shouldPlay: true, positionMillis: millis })`.

  Playback may not start immediately after calling this function for reasons such as buffering. Make sure to update your UI based on the `isPlaying` and `isBuffering` properties of the `PlaybackStatus` (described below).

- `playbackObject.playFromPositionAsync(millis, { toleranceMillisBefore, toleranceMillisAfter })`

  This is equivalent to `playbackObject.setStatusAsync({ shouldPlay: true, positionMillis: millis, seekMillisToleranceBefore: toleranceMillisBefore, seekMillisToleranceAfter: toleranceMillisAfter })`. The tolerances are used only on iOS ([more details](#what-is-seek-tolerance-and-why-would-i-want-to-use-it-ios-only)).

  Playback may not start immediately after calling this function for reasons such as buffering. Make sure to update your UI based on the `isPlaying` and `isBuffering` properties of the `PlaybackStatus` (described below).

  #### Parameters

  - **millis (_number_)** -- The desired position of playback in milliseconds.

- `playbackObject.pauseAsync()`

  This is equivalent to `playbackObject.setStatusAsync({ shouldPlay: false })`.

- `playbackObject.stopAsync()`

  This is equivalent to `playbackObject.setStatusAsync({ shouldPlay: false, positionMillis: 0 })`.

- `playbackObject.setPositionAsync(millis)`

  This is equivalent to `playbackObject.setStatusAsync({ positionMillis: millis })`.

- `playbackObject.setPositionAsync(millis, { toleranceMillisBefore, toleranceMillisAfter })`

  This is equivalent to `playbackObject.setStatusAsync({ positionMillis: millis, seekMillisToleranceBefore: toleranceMillisBefore, seekMillisToleranceAfter: toleranceMillisAfter })`. The tolerances are used only on iOS ([more details](#what-is-seek-tolerance-and-why-would-i-want-to-use-it-ios-only)).

  #### Parameters

  - **millis (_number_)** -- The desired position of playback in milliseconds.

- `playbackObject.setRateAsync(value, shouldCorrectPitch, pitchCorrectionQuality)`

  This is equivalent to `playbackObject.setStatusAsync({ rate: value, shouldCorrectPitch: shouldCorrectPitch, pitchCorrectionQuality: pitchCorrectionQuality })`.

  #### Parameters

  - **value (_number_)** -- The desired playback rate of the media. This value must be between `0.0` and `32.0`. Only available on Android API version 23 and later and iOS.

  - **shouldCorrectPitch (_boolean_)** -- A boolean describing if we should correct the pitch for a changed rate. If set to `true`, the pitch of the audio will be corrected (so a rate different than `1.0` will timestretch the audio).

  - **pitchCorrectionQuality (_Audio.PitchCorrectionQuality_)** -- iOS time pitch algorithm setting, defaults to `Audio.PitchCorrectionQuality.Low`. Available values:

    `Low` - equivalent to `AVAudioTimePitchAlgorithmLowQualityZeroLatency`

    `Medium` - equivalent to `AVAudioTimePitchAlgorithmTimeDomain`

    `High` - equivalent to `AVAudioTimePitchAlgorithmSpectral`

    Check official Apple docs for more info https://developer.apple.com/documentation/avfoundation/avaudiotimepitchalgorithmlowqualityzerolatency

- `playbackObject.setVolumeAsync(value)`

  This is equivalent to `playbackObject.setStatusAsync({ volume: value })`.

  #### Parameters

  - **value (_number_)** -- A number between `0.0` (silence) and `1.0` (maximum volume).

- `playbackObject.setIsMutedAsync(value)`

  This is equivalent to `playbackObject.setStatusAsync({ isMuted: value })`.

  #### Parameters

  - **value (_boolean_)** -- A boolean describing if the audio of this media should be muted.

- `playbackObject.setIsLoopingAsync(value)`

  This is equivalent to `playbackObject.setStatusAsync({ isLooping: value })`.

  #### Parameters

  - **value (_boolean_)** -- A boolean describing if the media should play once (`false`) or loop indefinitely (`true`).

- `playbackObject.setProgressUpdateIntervalAsync(millis)`

  This is equivalent to `playbackObject.setStatusAsync({ progressUpdateIntervalMillis: millis })`.

  #### Parameters

  - **millis (_number_)** -- The new minimum interval in milliseconds between calls of `onPlaybackStatusUpdate`. See `setOnPlaybackStatusUpdate()` for details.

## Playback Status

Most of the preceding API calls revolve around passing or returning the _status_ of the `playbackObject`.

- `PlaybackStatus`

  This is the structure returned from all playback API calls and describes the state of the `playbackObject` at that point in time. It is a dictionary with the following key-value pairs.

  If the `playbackObject` is not loaded, it will contain the following key-value pairs:

  - `isLoaded` : a boolean set to `false`.
  - `error` : a string only present if the `playbackObject` just encountered a fatal error and forced unload.

  Otherwise, it contains all of the following key-value pairs:

  - `isLoaded` : a boolean set to `true`.
  - `uri` : the location of the media source.
  - `progressUpdateIntervalMillis` : the minimum interval in milliseconds between calls of `onPlaybackStatusUpdate`. See `setOnPlaybackStatusUpdate()` for details.
  - `durationMillis` : the duration of the media in milliseconds. This is only present if the media has a duration (note that in some cases, a media file's duration is readable on Android, but not on iOS).
  - `positionMillis` : the current position of playback in milliseconds.
  - `playableDurationMillis` : the position until which the media has been buffered into memory. Like `durationMillis`, this is only present in some cases.
  - `shouldPlay` : a boolean describing if the media is supposed to play.
  - `isPlaying` : a boolean describing if the media is currently playing.
  - `isBuffering` : a boolean describing if the media is currently buffering.
  - `rate` : the current rate of the media.
  - `shouldCorrectPitch` : a boolean describing if we are correcting the pitch for a changed rate.
  - `pitchCorrectionQuality` : iOS time pitch algorithm setting. See `setRateAsync` for details.
  - `volume` : the current volume of the audio for this media.
  - `isMuted` : a boolean describing if the audio of this media is currently muted.
  - `isLooping` : a boolean describing if the media is currently looping.
  - `didJustFinish` : a boolean describing if the media just played to completion at the time that this status was received. When the media plays to completion, the function passed in `setOnPlaybackStatusUpdate()` is called exactly once with `didJustFinish` set to `true`. `didJustFinish` is never `true` in any other case.

- `PlaybackStatusToSet`

  This is the structure passed to `setStatusAsync()` to modify the state of the `playbackObject`. It is a dictionary with the following key-value pairs, all of which are optional.

  - `progressUpdateIntervalMillis` : the new minimum interval in milliseconds between calls of `onPlaybackStatusUpdate`. See `setOnPlaybackStatusUpdate()` for details.
  - `positionMillis` : the desired position of playback in milliseconds.
  - `seekMillisToleranceBefore` : the tolerance in milliseconds with which seek will be applied to the player. _[iOS only, [details](#what-is-seek-tolerance-and-why-would-i-want-to-use-it-ios-only)]_
  - `seekMillisToleranceAfter` : the tolerance in milliseconds with which seek will be applied to the player. _[iOS only, [details](#what-is-seek-tolerance-and-why-would-i-want-to-use-it-ios-only)]_
  - `shouldPlay` : a boolean describing if the media is supposed to play. Playback may not start immediately after setting this value for reasons such as buffering. Make sure to update your UI based on the `isPlaying` and `isBuffering` properties of the `PlaybackStatus`.
  - `rate` : the desired playback rate of the media. This value must be between `0.0` and `32.0`. Only available on Android API version 23 and later and iOS.
  - `shouldCorrectPitch` : a boolean describing if we should correct the pitch for a changed rate. If set to `true`, the pitch of the audio will be corrected (so a rate different than `1.0` will timestretch the audio).
  - `pitchCorrectionQuality` : iOS time pitch algorithm setting. Values: `Audio.PitchCorrectionQuality.Low`, `Audio.PitchCorrectionQuality.Medium`, or `Audio.PitchCorrectionQuality.High`.
  - `volume` : the desired volume of the audio for this media. This value must be between `0.0` (silence) and `1.0` (maximum volume).
  - `isMuted` : a boolean describing if the audio of this media should be muted.
  - `isLooping` : a boolean describing if the media should play once (`false`) or loop indefinitely (`true`).
  - `androidImplementation` : underlying implementation to use (when set to `MediaPlayer` it uses [Android's MediaPlayer](https://developer.android.com/reference/android/media/MediaPlayer.html), uses [ExoPlayer](https://google.github.io/ExoPlayer/) otherwise). You may need to use this property if you're trying to play an item unsupported by ExoPlayer ([formats supported by ExoPlayer](https://google.github.io/ExoPlayer/supported-formats.html), [formats supported by Android's MediaPlayer](https://developer.android.com/guide/appendix/media-formats.html#formats-table)). Note that setting this property takes effect only when the AV object is just being created (toggling its value later will do nothing). _[Android only]_

  Note that a `rate` different than `1.0` is currently only available on Android API version 23 and later and iOS.

  Note that `volume` and `isMuted` only affect the audio of this `playbackObject` and do NOT affect the system volume.

### Default initial `PlaybackStatusToSet`

The default initial `PlaybackStatusToSet` of all `Audio.Sound` objects and `Video` components is as follows:

```javascript
{
  progressUpdateIntervalMillis: 500,
  positionMillis: 0,
  shouldPlay: false,
  rate: 1.0,
  shouldCorrectPitch: false,
  volume: 1.0,
  isMuted: false,
  isLooping: false,
}
```

This default initial status can be overwritten by setting the optional `initialStatus` in `loadAsync()` or `Audio.Sound.createAsync()`.

### What is seek tolerance and why would I want to use it [iOS only]

When asked to seek an A/V item, native player in iOS sometimes may seek to a slightly different time. This technique, mentioned in [Apple documentation](https://developer.apple.com/documentation/avfoundation/avplayer/1387741-seek#discussion), is used to shorten the time of the `seekTo` call (the player may decide to play immediately from a different time than requested, instead of decoding the exact requested part and playing it with the decoding delay).

If you matter about the precision more than about the delay, you can specify the tolerance with which the player will seek according to your needs.

## Example usage

#### Example: `setOnPlaybackStatusUpdate()`

```javascript
_onPlaybackStatusUpdate = playbackStatus => {
  if (!playbackStatus.isLoaded) {
    // Update your UI for the unloaded state
    if (playbackStatus.error) {
      console.log(`Encountered a fatal error during playback: ${playbackStatus.error}`);
      // Send Expo team the error on Slack or the forums so we can help you debug!
    }
  } else {
    // Update your UI for the loaded state

    if (playbackStatus.isPlaying) {
      // Update your UI for the playing state
    } else {
      // Update your UI for the paused state
    }

    if (playbackStatus.isBuffering) {
      // Update your UI for the buffering state
    }

    if (playbackStatus.didJustFinish && !playbackStatus.isLooping) {
      // The player has just finished playing and will stop. Maybe you want to play something else?
    }

    ... // etc
  }
};

... // Load the playbackObject and obtain the reference.
playbackObject.setOnPlaybackStatusUpdate(this._onPlaybackStatusUpdate);
...
```

#### Example: Loop media exactly 20 times

```javascript
const N = 20;
...

_onPlaybackStatusUpdate = (playbackStatus) => {
  if (playbackStatus.didJustFinish) {
    if (this.state.numberOfLoops == N - 1) {
      playbackObject.setIsLooping(false);
    }
    this.setState({ numberOfLoops: this.state.numberOfLoops + 1 });
  }
};

...
this.setState({ numberOfLoops: 0 });
... // Load the playbackObject and obtain the reference.
playbackObject.setOnPlaybackStatusUpdate(this._onPlaybackStatusUpdate);
playbackObject.setIsLooping(true);
...
```

#
