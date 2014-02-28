/*
 * Copyright 2012 ZXing authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@protocol ZXCaptureDelegate, ZXReader;
@class ZXDecodeHints;

@interface ZXCapture : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate, CAAction>

@property (nonatomic, weak) id<ZXCaptureDelegate> delegate;
@property (nonatomic, copy) NSString *captureToFilename;
@property (nonatomic) CGAffineTransform transform;
@property (nonatomic, readonly) AVCaptureVideoDataOutput *output;
@property (nonatomic, readonly) CALayer *layer;
@property (nonatomic, retain) AVCaptureDevice *captureDevice;
@property (nonatomic, assign) BOOL mirror;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, retain) id<ZXReader> reader;
@property (nonatomic, retain) ZXDecodeHints *hints;
@property (nonatomic, assign) CGFloat rotation;
@property (nonatomic, readonly) BOOL hasFront;
@property (nonatomic, readonly) BOOL hasBack;
@property (nonatomic, readonly) BOOL hasTorch;
@property (nonatomic, readonly) int front;
@property (nonatomic, readonly) int back;
@property (nonatomic) int camera;
@property (nonatomic) BOOL torch;

- (CALayer *)luminance;
- (void)setLuminance:(BOOL)on_off;
- (CALayer *)binary;
- (void)setBinary:(BOOL)on_off;
- (void)start;
- (void)stop;
- (void)hard_stop;
- (void)order_skip;

@end
