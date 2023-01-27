#import "RNLiveAudioStream.h"

@implementation RNLiveAudioStream

RCT_EXPORT_MODULE();

+ (BOOL)requiresMainQueueSetup {
  return YES;
}

RCT_EXPORT_METHOD(init:(NSDictionary *) options) {
    RCTLogInfo(@"%s init", kModule);

    // cleanup structures
    memset(&_recordState.mDataFormat, 0, sizeof(_recordState.mDataFormat));
    //memset(&_recordState.mTargetDataFormat, 0, sizeof(_recordState.mTargetDataFormat));

    _recordState.mDataFormat.mSampleRate        = options[@"sampleRate"] == nil ? 44100 : [options[@"sampleRate"] doubleValue];
    _recordState.mDataFormat.mBitsPerChannel    = options[@"bitsPerSample"] == nil ? 16 : [options[@"bitsPerSample"] unsignedIntValue];
    _recordState.mDataFormat.mChannelsPerFrame  = options[@"channels"] == nil ? 1 : [options[@"channels"] unsignedIntValue];
    _recordState.mDataFormat.mBytesPerPacket    = (_recordState.mDataFormat.mBitsPerChannel / 8) * _recordState.mDataFormat.mChannelsPerFrame;
    _recordState.mDataFormat.mBytesPerFrame     = _recordState.mDataFormat.mBytesPerPacket;
    _recordState.mDataFormat.mFramesPerPacket   = 1;
    _recordState.mDataFormat.mReserved          = 0;
    _recordState.mDataFormat.mFormatID          = kAudioFormatULaw;
    _recordState.mDataFormat.mFormatFlags       = _recordState.mDataFormat.mBitsPerChannel == 8 ? kLinearPCMFormatFlagIsPacked : (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked);
    _recordState.bufferByteSize                 = kBufferSize;

    _recordState.mSelf = self;
    _recordState.encodeConvertRef = NULL;
    
    // copy parameters into target modified to fit AAC
    RCTLogInfo(@"%s Source format is %d", kModule, _recordState.mDataFormat.mFormatID);
    RCTLogInfo(@"%s Target sample rate is %f", kModule, _recordState.mDataFormat.mSampleRate);

    // create playing mutex
    _recordState.playLock = [[NSLock alloc] init];
    _recordState.playModeSpeaker = false;
}

RCT_EXPORT_METHOD(
    play:(NSString *) data
    resolver:(RCTPromiseResolveBlock)resolve
    rejecter:(RCTPromiseRejectBlock)reject
) {
    OSStatus status;
    RCTLogInfo(@"%s playing", kModule);
    if([self setupAudioSession:true] != true){
        reject(@"E_AUDIO_SESSION", @"Failed to setup audio session", nil);
        return;
    }

    _recordState.mIsPlaying = true;

    // create player
    RCTLogInfo(@"%s creating audio output", kModule);
    if((status = AudioQueueNewOutput(&_recordState.mDataFormat, HandleOutputBuffer, &_recordState, NULL, NULL, 0, &(_recordState.playQueue))) != noErr){
        RCTLogInfo(@"%s failed to create output! (status %i)", kModule, status);
        reject(@"E_QUEUE_OUTPUT", @"Failed to create audio output", nil);
        return;
    }
    
    if((status = AudioQueueSetParameter(_recordState.playQueue, kAudioQueueParam_Volume, 1.0)) != noErr){
        RCTLogInfo(@"%s failed to setup volume gain! (status %i)", kModule, status);
        reject(@"E_QUEUE_PARAM", @"Failed to setup volume gain!", nil);
        return;
    }

    // allocate player buffer
    for(int i = 0; i < kPlayBuffers; i++){
        AudioQueueAllocateBuffer(_recordState.playQueue, kPlayBufferSize*2, &_recordState.playBuffers[i]);
        AudioQueueEnqueueBuffer(_recordState.playQueue, _recordState.playBuffers[i], 0, NULL);
    }
    
    // decode base64 data
    RCTLogInfo(@"%s decoding base64", kModule);
    _recordState.playData = [[NSMutableData alloc]initWithBase64EncodedString:data options:0];
    // store audio data
    _recordState.playDataLen = (UInt32) [_recordState.playData length];

    RCTLogInfo(@"%s got %d audioData bytes", kModule, _recordState.playDataLen);

    // fill out buffers
    for(int i = 0; i < kPlayBuffers; i++){
        [self FillOutputBuffer:_recordState.playQueue queueBuffer:_recordState.playBuffers[i]];
    }

    // start playing
    if(AudioQueueStart(_recordState.playQueue, NULL) != noErr){
        RCTLog(@"%s failed to start audioQueue", kModule);
        reject(@"E_QUEUE_START", @"Failed to start audioQueue", nil);
        return;
    }

    RCTLogInfo(@"%s play queue started!", kModule);
    resolve(nil);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(stopPlaying) {
    RCTLogInfo(@"%s stop playing", kModule);
    if (_recordState.mIsPlaying) {
        _recordState.mIsPlaying = false;

        // stop playing
        AudioQueueFlush(_recordState.playQueue);
        AudioQueueReset(_recordState.playQueue);
        AudioQueueStop(_recordState.playQueue, true);

        // free audio queues
        for(int i = 0; i < kPlayBuffers; i++){
            AudioQueueFreeBuffer(_recordState.playQueue, _recordState.playBuffers[i]);
        }
    }

    return nil;
}

RCT_EXPORT_METHOD(start:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    RCTLogInfo(@"%s start", kModule);

    if(![self setupAudioSession:false]){
        reject(@"E_AUDIO_SESSION", @"Failed to setup audio session", nil);
        return;
    }

    _recordState.mIsRunning = true;

    OSStatus status = AudioQueueNewInput(&_recordState.mDataFormat, HandleInputBuffer, &_recordState, NULL, NULL, 0, &_recordState.mQueue);
    if (status != 0) {
        RCTLog(@"%s Record Failed. Cannot initialize AudioQueueNewInput. status: %i", kModule, (int) status);
        reject(@"E_QUEUE_INPUT", @"Failed to create audio input", nil);
        return;
    }

    for (int i = 0; i < kNumberBuffers; i++) {
        AudioQueueAllocateBuffer(_recordState.mQueue, _recordState.bufferByteSize, &_recordState.mBuffers[i]);
        AudioQueueEnqueueBuffer(_recordState.mQueue, _recordState.mBuffers[i], 0, NULL);
    }

    // allocate output buffer
    _recordState.outBuffer = [NSMutableData data];
    AudioQueueStart(_recordState.mQueue, NULL);
    resolve(nil);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(stop) {
    RCTLogInfo(@"%s stop", kModule);
    if (_recordState.mIsRunning) {
        _recordState.mIsRunning = false;

        // free audio queues
        AudioQueueStop(_recordState.mQueue, true);

        RCTLogInfo(@"%s sending data with %lu bytes", kModule, _recordState.outBufferLen);
        NSString *str = [_recordState.outBuffer base64EncodedStringWithOptions:0];

        for (int i = 0; i < kNumberBuffers; i++) {
            AudioQueueFreeBuffer(_recordState.mQueue, _recordState.mBuffers[i]);
        }

        // free up buffer and reset
        _recordState.outBufferLen = 0;

        return str;
    }

    return nil;
}

RCT_EXPORT_METHOD(setSpeaker:(BOOL) enabled){
    _recordState.playModeSpeaker = enabled;
    if(_recordState.mIsPlaying){
        [self setupAudioSession:true];
    }
}

- (bool) setupAudioSession:(BOOL) playMode {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error = nil;
    BOOL success;

    // Apple recommended:
    // Instead of setting your category and mode properties independently, set them at the same time
    success = [audioSession setCategory: AVAudioSessionCategoryPlayAndRecord
                                mode: (playMode && _recordState.playModeSpeaker ? AVAudioSessionModeDefault : AVAudioSessionModeVoiceChat)
                                options: AVAudioSessionCategoryOptionDuckOthers |
                                        AVAudioSessionCategoryOptionAllowBluetooth |
                                        AVAudioSessionCategoryOptionAllowAirPlay
                                error: &error];
    if (!success || error != nil) {
        RCTLog(@"[RNLiveAudioStream] Problem setting up AVAudioSession category and mode. Error: %@", error);
        return false;
    }

    // recording mode
    if(!playMode){
        return true;
    }

    // playback mode
    [audioSession setPreferredSampleRate:_recordState.mDataFormat.mSampleRate error:nil];
    [audioSession setPreferredOutputNumberOfChannels:1 error:nil];
    [audioSession overrideOutputAudioPort:(_recordState.playModeSpeaker ? AVAudioSessionPortOverrideSpeaker : AVAudioSessionPortOverrideNone) error:nil];
    [audioSession setActive:YES error:nil];
    RCTLog(@"%s mode set to %s", kModule, _recordState.playModeSpeaker ? "speaker" : "earpiece");

    return true;
}

static void HandleInputBuffer(
    void *inUserData,
    AudioQueueRef inAQ,
    AudioQueueBufferRef inBuffer,
    const AudioTimeStamp *inStartTime,
    UInt32 inNumPackets,
    const AudioStreamPacketDescription *inPacketDesc
) {
    AQRecordState* pRecordState = (AQRecordState *)inUserData;

    if (!pRecordState->mIsRunning) {
        return;
    }

    // without converter
    //if(kOutputFormat != kAudioFormatMPEG4AAC){
        RCTLogInfo(@"%s recording, packets: %d, size: %d", kModule, inNumPackets, inBuffer->mAudioDataByteSize);

        // deliver AAC data to user
        [pRecordState->outBuffer appendBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
        long nsamples = inBuffer->mAudioDataByteSize;

        RCTLogInfo(@"Recorded %lu bytes", pRecordState->outBufferLen);
        pRecordState->outBufferLen += nsamples;
        AudioQueueEnqueueBuffer(pRecordState->mQueue, inBuffer, 0, NULL);
        return;
    //}
    
    // clear queue buffer
    //AudioQueueEnqueueBuffer(pRecordState->mQueue, inBuffer, 0, NULL);
}

static void HandleOutputBuffer(
    void *inUserData,
    AudioQueueRef inAQ,
    AudioQueueBufferRef buffer
) {
    AQRecordState *pRecordState = (AQRecordState *) inUserData;

    if(!pRecordState->mIsPlaying){
        return;
    }

    [pRecordState->mSelf FillOutputBuffer:inAQ queueBuffer:buffer];
}

- (void) FillOutputBuffer:(AudioQueueRef)queue queueBuffer:(AudioQueueBufferRef)buffer {
    // mutex is needed for thread concurrency
    [_recordState.playLock lock];

    NSUInteger length = [_recordState.playData length];
    
    // hasData?
    if (length > 0) {
        RCTLogInfo(@"%s playing %d of %d bytes", kModule, length, _recordState.playDataLen);
        NSRange range;
        // if playdata doesnt fit into bufferSize, make range with buffer size
        if (length > kPlayBufferSize) {
            range = NSMakeRange(0, kPlayBufferSize);
        } else {
            range = NSMakeRange(0, length);
        }

        // retrieve data with range
        NSData *bufferedData = [_recordState.playData subdataWithRange:range];
        // copy into audio buffer
        memcpy(buffer->mAudioData, bufferedData.bytes, bufferedData.length);
        // setup buffer parameters
        buffer->mAudioDataByteSize = (UInt32) bufferedData.length;
        buffer->mPacketDescriptionCount = 0;
        AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
        // move buffer to next position
        [_recordState.playData replaceBytesInRange:range withBytes:NULL length:0];
    } else {
        AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    }

    /*RCTLogInfo(@"%s playing %d", kModule, (UInt32) _recordState.playData.length);
    memcpy(buffer->mAudioData, _recordState.playData.bytes, _recordState.playData.length);
    buffer->mAudioDataByteSize = (UInt32) _recordState.playData.length;
    AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);*/
    [_recordState.playLock unlock];
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"data"];
}

- (void)dealloc {
    [self stopPlaying];
    [self stop];

    RCTLogInfo(@"%s dealloc", kModule);
    AudioQueueDispose(_recordState.mQueue, true);
    AudioQueueDispose(_recordState.playQueue, true);
}

@end
