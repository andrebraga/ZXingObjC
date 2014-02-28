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

#import "ZXCapture.h"
#import "ZXCaptureDelegate.h"
#import "ZXCGImageLuminanceSource.h"
#import "ZXBinaryBitmap.h"
#import "ZXDecodeHints.h"
#import "ZXHybridBinarizer.h"
#import "ZXMultiFormatReader.h"
#import "ZXReader.h"
#import "ZXResult.h"

#if TARGET_OS_EMBEDDED || TARGET_IPHONE_SIMULATOR
#import <UIKit/UIKit.h>
#endif

@interface ZXCapture () {
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

@property (nonatomic, strong) __attribute__((NSObject)) dispatch_queue_t captureQueue;
@property (nonatomic, strong) AVCaptureDeviceInput *input;
@property (nonatomic, assign) AVCaptureVideoPreviewLayer *layer;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoDataOutput *output;

@end

@implementation ZXCapture

- (ZXCapture *)init {
  if ((self = [super init])) {
    on_screen = running = NO;
    reported_width = 0;
    reported_height = 0;
    width = 1920;
    height = 1080;
    hard_stop = false;
    capture_device_index = -1;
    order_in_skip = 0;
    order_out_skip = 0;
    _transform = CGAffineTransformIdentity;
    _rotation = 0.0f;
    _reader = [ZXMultiFormatReader reader];
    _hints = [ZXDecodeHints hints];
    _captureQueue = dispatch_queue_create("com.zxing.captureQueue", NULL);
  }
  return self;
}


- (BOOL)running {return running;}

- (BOOL)mirror {
  return mirror;
}

- (void)setMirror:(BOOL)mirror_ {
  if (mirror != mirror_) {
    mirror = mirror_;
    if (self.layer) {
      _transform.a = -_transform.a;
      [self.layer setAffineTransform:_transform];
    }
  }
}

- (void)order_skip {
  order_out_skip = order_in_skip = 1;
}

- (AVCaptureDevice *)device {
  if (self.captureDevice) {
    return self.captureDevice;
  }

  AVCaptureDevice *zxd = nil;

  NSArray *devices =
  [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];

  if ([devices count] > 0) {
    if (capture_device_index == -1) {
      AVCaptureDevicePosition position = AVCaptureDevicePositionBack;
      if (camera == self.front) {
        position = AVCaptureDevicePositionFront;
      }

      for(unsigned int i=0; i < [devices count]; ++i) {
        AVCaptureDevice *dev = [devices objectAtIndex:i];
        if (dev.position == position) {
          capture_device_index = i;
          zxd = dev;
          break;
        }
      }
    }
    
    if (!zxd && capture_device_index != -1) {
      zxd = [devices objectAtIndex:capture_device_index];
    }
  }

  if (!zxd) {
    zxd =  [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  }

  _captureDevice = zxd;

  return zxd;
}

- (void)replaceInput {
  [self.session beginConfiguration];

  if (self.session && self.input) {
    [self.session removeInput:self.input];
    self.input = nil;
  }

  AVCaptureDevice *zxd = [self device];

  if (zxd) {
    self.input = [AVCaptureDeviceInput deviceInputWithDevice:zxd error:nil];
  }
  
  if (self.input) {
    self.session.sessionPreset = AVCaptureSessionPresetMedium;
    [self.session addInput:self.input];
  }

  [self.session commitConfiguration];
}

- (AVCaptureSession *)session {
  if (!_session) {
    _session = [[AVCaptureSession alloc] init];
    [self replaceInput];
  }
  return _session;
}

- (void)stop {
  // NSLog(@"stop");

  if (!running) {
    return;
  }

  if (self.session.running) {
    // NSLog(@"stop running");
    [self.layer removeFromSuperlayer];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      [self.session stopRunning];
    });
  } else {
    // NSLog(@"already stopped");
  }
  running = false;
}

- (AVCaptureVideoDataOutput *)output {
  if (!_output) {
    _output = [[AVCaptureVideoDataOutput alloc] init];
    [_output setVideoSettings:@{
      (NSString *)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA]
    }];
    [_output setAlwaysDiscardsLateVideoFrames:YES];
    [_output setSampleBufferDelegate:self queue:_captureQueue];

    [self.session addOutput:_output];
  }

  return _output;
}

- (void)start {
  // NSLog(@"start %@ %d %@ %@", self.session, running, output, delegate);

  if (hard_stop) {
    return;
  }

  if (self.delegate || luminance || binary) {
    // for side effects
    [self output];
  }
    
  if (self.session.running) {
    // NSLog(@"already running");
  } else {

    static int i = 0;
    if (++i == -2) {
      abort();
    }

    // NSLog(@"start running");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      [self.session startRunning];
    });
  }
  running = true;
}

- (void)start_stop {
  // NSLog(@"ss %d %@ %d %@ %@ %@", running, delegate, on_screen, output, luminanceLayer, binary);
  if ((!running && (self.delegate || on_screen)) ||
      (!self.output &&
       (self.delegate ||
        (on_screen && (luminance || binary))))) {
    [self start];
  }
  if (running && !self.delegate && !on_screen) {
    [self stop];
  }
}

- (void)setDelegate:(id<ZXCaptureDelegate>)delegate {
  _delegate = delegate;
  if (delegate) {
    hard_stop = false;
  }
  [self start_stop];
}

- (void)hard_stop {
  hard_stop = true;
  if (running) {
    [self stop];
  }
}

- (void)setLuminance:(BOOL)on {
  if (on && !luminance) {
    luminance = [CALayer layer];
  } else if (!on && luminance) {
    luminance = nil;
  }
}

- (CALayer *)luminance {
  return luminance;
}

- (void)setBinary:(BOOL)on {
  if (on && !binary) {
    binary = [CALayer layer];
  } else if (!on && binary) {
    binary = nil;
  }
}

- (CALayer *)binary {
  return binary;
}

- (CALayer *)layer {
  AVCaptureVideoPreviewLayer *layer = (AVCaptureVideoPreviewLayer *)_layer;
  if (!_layer) {
    layer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];

    layer.videoGravity = AVLayerVideoGravityResizeAspect;
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [layer setAffineTransform:self.transform];
    layer.delegate = self;

    self.layer = layer;
  }
  return layer;
}

- (void)runActionForKey:(NSString *)key
                 object:(id)anObject
              arguments:(NSDictionary *)dict {
  // NSLog(@" rAFK %@ %@ %@", key, anObject, dict); 
  (void)anObject;
  (void)dict;
  if ([key isEqualToString:kCAOnOrderIn]) {
    
    if (order_in_skip) {
      --order_in_skip;
      // NSLog(@"order in skip");
      return;
    }

    // NSLog(@"order in");

    on_screen = true;
    if (luminance && luminance.superlayer != self.layer) {
      // [layer addSublayer:luminance];
    }
    if (binary && binary.superlayer != self.layer) {
      // [layer addSublayer:binary];
    }
    [self start_stop];
  } else if ([key isEqualToString:kCAOnOrderOut]) {
    if (order_out_skip) {
      --order_out_skip;
      // NSLog(@"order out skip");
      return;
    }

    on_screen = false;
    // NSLog(@"order out");
    [self start_stop];
  }
}

- (id<CAAction>)actionForLayer:(CALayer *)_layer forKey:(NSString *)event {
  // NSLog(@"layer event %@", event);

  // never animate
  [CATransaction setValue:[NSNumber numberWithFloat:0.0f]
                   forKey:kCATransactionAnimationDuration];

  // NSLog(@"afl %@ %@", _layer, event);
  if ([event isEqualToString:kCAOnOrderIn]
      || [event isEqualToString:kCAOnOrderOut]
      // || ([event isEqualToString:@"bounds"] && (binary || luminance))
      // || ([event isEqualToString:@"onLayout"] && (binary || luminance))
    ) {
    return self;
  } else if ([event isEqualToString:@"contents"] ) {
  } else if ([event isEqualToString:@"sublayers"] ) {
  } else if ([event isEqualToString:@"onLayout"] ) {
  } else if ([event isEqualToString:@"position"] ) {
  } else if ([event isEqualToString:@"bounds"] ) {
  } else if ([event isEqualToString:@"layoutManager"] ) {
  } else if ([event isEqualToString:@"transform"] ) {
  } else {
    NSLog(@"afl %@ %@", self.layer, event);
  }
  return nil;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
  @autoreleasepool {
    if (!cameraIsReady)
    {
      cameraIsReady = YES;
      if ([self.delegate respondsToSelector:@selector(captureCameraIsReady:)])
      {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.delegate captureCameraIsReady:self];
        });
      }
    }
             
    if (!self.captureToFilename && !luminance && !binary && !self.delegate) {
      // NSLog(@"skipping capture");
      return;
    }

    // NSLog(@"received frame");

    CVImageBufferRef videoFrame = CMSampleBufferGetImageBuffer(sampleBuffer);

    // NSLog(@"%ld %ld", CVPixelBufferGetWidth(videoFrame), CVPixelBufferGetHeight(videoFrame));
    // NSLog(@"delegate %@", delegate);

    (void)sampleBuffer;
    (void)captureOutput;
    (void)connection;

    // The routines don't exist in iOS. There are alternatives, but a good
    // solution would have to figure out a reasonable path and might be
    // better as a post to url

    if (self.captureToFilename) {
      CGImageRef image = 
        [ZXCGImageLuminanceSource createImageFromBuffer:videoFrame];
      NSURL *url = [NSURL fileURLWithPath:self.captureToFilename];
      CGImageDestinationRef dest =
        CGImageDestinationCreateWithURL((__bridge CFURLRef)url, (__bridge CFStringRef)@"public.png", 1, nil);
      CGImageDestinationAddImage(dest, image, nil);
      CGImageDestinationFinalize(dest);
      CGImageRelease(image);
      CFRelease(dest);
      self.captureToFilename = nil;
    }

    CGImageRef videoFrameImage = [ZXCGImageLuminanceSource createImageFromBuffer:videoFrame];
    CGImageRef rotatedImage = [self createRotatedImage:videoFrameImage degrees:self.rotation];
    CGImageRelease(videoFrameImage);

    ZXCGImageLuminanceSource *source = [[ZXCGImageLuminanceSource alloc] initWithCGImage:rotatedImage];
    CGImageRelease(rotatedImage);

    if (luminance) {
      CGImageRef image = source.image;
      CGImageRetain(image);
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), dispatch_get_main_queue(), ^{
          luminance.contents = (__bridge id)image;
          CGImageRelease(image);
        });
    }

    if (binary || self.delegate) {
      ZXHybridBinarizer *binarizer = [[ZXHybridBinarizer alloc] initWithSource:source];

      if (binary) {
        CGImageRef image = [binarizer createImage];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), dispatch_get_main_queue(), ^{
          binary.contents = (__bridge id)image;
          CGImageRelease(image);
        });
      }

      if (self.delegate) {
        ZXBinaryBitmap *bitmap = [[ZXBinaryBitmap alloc] initWithBinarizer:binarizer];

        NSError *error;
        ZXResult *result = [self.reader decode:bitmap hints:self.hints error:&error];
        if (result) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate captureResult:self result:result];
          });
        }
      }
    }
  }
}

- (BOOL)hasFront {
  NSArray *devices = 
    [AVCaptureDevice
     devicesWithMediaType:AVMediaTypeVideo];
  return [devices count] > 1;
}

- (BOOL)hasBack {
  NSArray *devices = 
    [AVCaptureDevice
        devicesWithMediaType: AVMediaTypeVideo];
  return [devices count] > 0;
}

- (BOOL)hasTorch {
  if ([self device]) {
    return [self device].hasTorch;
  } else {
    return NO;
  }
}

- (int)front {
  return 0;
}

- (int)back {
  return 1;
}

- (int)camera {
  return camera;
}

- (BOOL)torch {
  return torch;
}

- (void)setCamera:(int)camera_ {
  if (camera  != camera_) {
    camera = camera_;
    capture_device_index = -1;
    self.captureDevice = nil;
    [self replaceInput];
  }
}

- (void)setTorch:(BOOL)torch_ {
  torch = torch_;
  [self.input.device lockForConfiguration:nil];
  if (self.torch) {
    self.input.device.torchMode = AVCaptureTorchModeOn;
  } else {
    self.input.device.torchMode = AVCaptureTorchModeOff;
  }
  [self.input.device unlockForConfiguration];
}

- (void)setTransform:(CGAffineTransform)transform_ {
  self.transform = transform_;
  [self.layer setAffineTransform:transform_];
}

// Adapted from http://blog.coriolis.ch/2009/09/04/arbitrary-rotation-of-a-cgimage/ and https://github.com/JanX2/CreateRotateWriteCGImage
- (CGImageRef)createRotatedImage:(CGImageRef)original degrees:(float)degrees CF_RETURNS_RETAINED {
  if (degrees == 0.0f) {
    CGImageRetain(original);
    return original;
  } else {
    double radians = degrees * M_PI / 180;

#if TARGET_OS_EMBEDDED || TARGET_IPHONE_SIMULATOR
    radians = -1 * radians;
#endif

    size_t _width = CGImageGetWidth(original);
    size_t _height = CGImageGetHeight(original);

    CGRect imgRect = CGRectMake(0, 0, _width, _height);
    CGAffineTransform __transform = CGAffineTransformMakeRotation(radians);
    CGRect rotatedRect = CGRectApplyAffineTransform(imgRect, __transform);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 rotatedRect.size.width,
                                                 rotatedRect.size.height,
                                                 CGImageGetBitsPerComponent(original),
                                                 0,
                                                 colorSpace,
                                                 kCGBitmapAlphaInfoMask & kCGImageAlphaPremultipliedFirst);
    CGContextSetAllowsAntialiasing(context, FALSE);
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGColorSpaceRelease(colorSpace);

    CGContextTranslateCTM(context,
                          +(rotatedRect.size.width/2),
                          +(rotatedRect.size.height/2));
    CGContextRotateCTM(context, radians);

    CGContextDrawImage(context, CGRectMake(-imgRect.size.width/2,
                                           -imgRect.size.height/2,
                                           imgRect.size.width,
                                           imgRect.size.height),
                       original);

    CGImageRef rotatedImage = CGBitmapContextCreateImage(context);
    CFRelease(context);

    return rotatedImage;
  }
}

@end
