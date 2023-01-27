
# react-native-recording-base64

This module is modified from [react-native-live-audiostream](https://github.com/xiqi/react-native-live-audio-stream).
Instead of saving to an audio file, it only records audio data using uLaw codec. Recorded data are stored in-memory and then returned as base64 encoded string.
After sending over network you can easily play base64 encoded data again on the other side.

You have to only keep eye on recorded data size, with every second the buffer size is growing really fast, but not as fast like using linear PCM codec.
For example 30 seconds of audio record are equal to ~500kbytes which is acceptable for transfer over network thanks to the uLaw codec.

The additional support is for switching between phone's speaker and internal earpiece.

It would be really better to encode it into AAC or other codec, i was trying to make an implementation, but due to time pressure i was not able to give it another hours to make it work.

You can use this implementation like me for voice messages.

Most of the code was written by the respective original authors.

## Install
```
npm i https://github.com/binarybase/react-native-recording-base64
cd ios
pod install
```

## Add Microphone Permissions

### iOS
Add these lines to ```ios/[YOU_APP_NAME]/info.plist```
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need your permission to use the microphone.</string>
```

### Android
Currently not supported

## Usage
```javascript
import { NativeModules } from 'react-native';
const { RNLiveAudioStream } = NativeModules;

// initialize library
useEffect(() => {
    RNLiveAudioStream.init({
      // to record and play audio uLaw codec is used
      sampleRate: 8000,
      // bits per sample 8-bit
      bitsPerSample: 8
    });
}, []);

// to record audio in base64 format
const start = performance.now();
try {
  await RNLiveAudioStream.start();
} catch(ex){
  // handle errors like failed initialization of the audio buffer or sth else
}

// stop and receive recording audio
const recordedBase64Data = RNLiveAudioStream.stop();
// store duration to know when to stop playback
const duration = performance.now() - start;

// send over network
....

// play from base64 encoded format (uLaw codec)
RNLiveAudioStream.play(recordedBase64Data);
// stop playing after duration
setTimeout(() => RNLiveAudioStream.stop(), duration);


// if you want to switch between phone's internal earpiece and speaker you can use fn setSpeaker()
// switching can be also used while audio is playing
// @param {bool} enabled (false = earpiece, true = speaker)
RNLiveAudioStream.setSpeaker(true);
```

## Credits/References
- [BleVOIP](https://github.com/JustinYangJing/BleVOIP)
- [react-native-live-audio-stream](https://github.com/xiqi/react-native-live-audio-stream)
- [react-native-audio-record](https://github.com/goodatlas/react-native-audio-record)
- iOS [Audio Queues](https://developer.apple.com/library/content/documentation/MusicAudio/Conceptual/AudioQueueProgrammingGuide)
- Android [AudioRecord](https://developer.android.com/reference/android/media/AudioRecord.html)
- [cordova-plugin-audioinput](https://github.com/edimuj/cordova-plugin-audioinput)
- [react-native-recording](https://github.com/qiuxiang/react-native-recording)
- [SpeakHere](https://github.com/shaojiankui/SpeakHere)
- [ringdroid](https://github.com/google/ringdroid)

## License 
MIT
