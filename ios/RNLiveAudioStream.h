#import <AVFoundation/AVFoundation.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTLog.h>

#define kModule                 "[RNLiveAudioStream]"
#define kNumberBuffers          3
#define kPlayBuffers            2
#define kMaxSeconds             100
#define kBufferSize				1024
#define kPlayBufferSize         1024

typedef struct {
	__unsafe_unretained id      mSelf;
	AudioStreamBasicDescription mDataFormat;
	AudioStreamBasicDescription mTargetDataFormat;
	AudioQueueRef               mQueue;
	AudioQueueBufferRef         mBuffers[kNumberBuffers];
	UInt32                      bufferByteSize;
	SInt64                      mCurrentPacket;
	bool                        mIsRunning;

	AudioConverterRef           encodeConvertRef;
	NSMutableData               *outBuffer;
	long                        outBufferLen;

	AudioQueueRef               playQueue;
	AudioQueueBufferRef			playBuffers[kPlayBuffers];
	bool						mIsPlaying;
    UInt32                      playDataLen;
    NSLock                      *playLock;
    NSMutableData               *playData;
    BOOL                        playModeSpeaker;

} AQRecordState;


@interface RNLiveAudioStream: RCTEventEmitter <RCTBridgeModule>
	@property (nonatomic, assign) AQRecordState recordState;
@end


