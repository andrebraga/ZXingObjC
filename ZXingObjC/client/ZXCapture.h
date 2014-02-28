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
#import "ZXCaptureDelegate.h"

@protocol ZXReader;
@class ZXDecodeHints;

@interface ZXCapture : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate, CAAction> {
  AVCaptureSession *session;
  AVCaptureDeviceInput *input;
  AVCaptureVideoDataOutput *output;

  int order_in_skip;
  int order_out_skip;
  BOOL running;
  BOOL on_screen;
  CALayer *luminance;
  CALayer *binary;
  size_t width;
  size_t height;
  size_t reported_width;
  size_t reported_height;
  BOOL hard_stop;
  int camera;
  BOOL torch;
  BOOL mirror;
  int capture_device_index;
  BOOL cameraIsReady;
}

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

- (id)init;
- (CALayer *)luminance;
- (void)setLuminance:(BOOL)on_off;
- (CALayer *)binary;
- (void)setBinary:(BOOL)on_off;
- (void)start;
- (void)stop;
- (void)hard_stop;
- (void)order_skip;

@end
