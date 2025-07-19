//
//  MetalCam.m
//  metalTextureTest
//
//  Created by Joseph Chow on 6/28/18.
//

#import <simd/simd.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <MetalKit/MetalKit.h>
#import "MetalCam.h"

#define GL_UNSIGNED_INT_8_8_8_8_REV 0x8367

// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "ShaderTypes.h"

// The max number of command buffers in flight
static const NSUInteger kMaxBuffersInFlight = 3;
static const float kImagePlaneVertexData[16] = {
    -1.0, -1.0,  0.0, 1.0,
    1.0, -1.0,  1.0, 1.0,
    -1.0,  1.0,  0.0, 0.0,
    1.0,  1.0,  1.0, 0.0,
};


// Table of equivalent formats across CoreVideo, Metal, and OpenGL
static const AAPLTextureFormatInfo AAPLInteropFormatTable[] = {
    // Core Video Pixel Format,               Metal Pixel Format,            GL internalformat, GL format,   GL type
    { kCVPixelFormatType_32BGRA,              MTLPixelFormatBGRA8Unorm,      GL_RGBA,           GL_BGRA_EXT, GL_UNSIGNED_INT_8_8_8_8_REV },
    { kCVPixelFormatType_32BGRA,              MTLPixelFormatBGRA8Unorm_sRGB, GL_RGBA,           GL_BGRA_EXT, GL_UNSIGNED_INT_8_8_8_8_REV },
};

static NSDictionary* cvBufferProperties = @{
                                             (__bridge NSString*)kCVPixelBufferOpenGLCompatibilityKey : @YES,
                                             (__bridge NSString*)kCVPixelBufferMetalCompatibilityKey : @YES,
                                             };

static const NSUInteger AAPLNumInteropFormats = sizeof(AAPLInteropFormatTable) / sizeof(AAPLTextureFormatInfo);

// ============ METAL CAM VIEW IMPLEMENTATION ============== //

@implementation MetalCamView

-(void)drawRect:(CGRect)rect{
    if(!self.currentDrawable && !self.currentRenderPassDescriptor){
        NSLog(@"unable to render");
        return;
    }
   
    // adjust image based on current frame
    [self _updateImagePlaneWithFrame];
    
    // update the camera image.
    [self update];
    
   
}

- (void) setViewport:(CGRect) _viewport{
    self->_viewport = _viewport;
}

- (void) update {
    
    if (!_session) {
        return;
    }
    
    // if viewport hasn't been set to something other than 0, try to set the viewport
    // values to be 0,0,<auto calcualted width>, <auto calculated height>
    _viewport = [[UIScreen mainScreen] bounds];
    
    // set the current orientation
    orientation = [[UIApplication sharedApplication] statusBarOrientation];
    
   
    // Wait to ensure only kMaxBuffersInFlight are getting proccessed by any stage in the Metal
    //   pipeline (App, Metal, Drivers, GPU, etc)
    dispatch_semaphore_wait(self._inFlightSemaphore, DISPATCH_TIME_FOREVER);
    
    // Create a new command buffer for each renderpass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";
    
    // Add completion hander which signal _inFlightSemaphore when Metal and the GPU has fully
    //   finished proccssing the commands we're encoding this frame.  This indicates when the
    //   dynamic buffers, that we're writing to this frame, will no longer be needed by Metal
    //   and the GPU.
    __block dispatch_semaphore_t block_sema = self._inFlightSemaphore;
    // Retain our CVMetalTextureRefs for the duration of the rendering cycle. The MTLTextures
    //   we use from the CVMetalTextureRefs are not valid unless their parent CVMetalTextureRefs
    //   are retained. Since we may release our CVMetalTextureRef ivars during the rendering
    //   cycle, we must retain them separately here.
    CVBufferRef capturedImageTextureYRef = CVBufferRetain(_capturedImageTextureYRef);
    CVBufferRef capturedImageTextureCbCrRef = CVBufferRetain(_capturedImageTextureCbCrRef);
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(block_sema);
        CVBufferRelease(capturedImageTextureYRef);
        CVBufferRelease(capturedImageTextureCbCrRef);

    }];
    
    
    // update camera image
    [self _updateCameraImage];
    

    
    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor* renderPassDescriptor = self.currentRenderPassDescriptor;
    
    
    
    // If we've gotten a renderPassDescriptor we can render to the drawable, otherwise we'll skip
    //   any rendering this frame because we have no drawable to draw to
    if (renderPassDescriptor != nil) {
        //NSLog(@"Got render pass descriptor - we can render!");
        
        if(_cameraImage){
            renderPassDescriptor.colorAttachments[0].texture = _cameraTexture;
        }
        
        
        // Create a render command encoder so we can render into something
        id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MetalCamRenderEncoder";
        
        // DRAW PRIMATIVE
    
        [self _drawCapturedImageWithCommandEncoder:renderEncoder];
        
        
        // We're done encoding commands
        [renderEncoder endEncoding];
    }else{
        NSLog(@"Error - do not have render pass descriptor");
    }
   
   
    //update shared OpenGL pixelbuffer
    // if running in openFrameworks
    if(openglMode){
        [self _updateOpenGLTexture];
    }

//    if(ARBodyTrackingConfiguration.isSupported){
    if(ARBodyTrackingConfiguration.isSupported && _session.configuration.frameSemantics == ARFrameSemanticPersonSegmentationWithDepth){

        // update depth textures
        [self _updateMatteTextures: commandBuffer];
    }
   
    
    // Schedule a present once the framebuffer is complete using the current drawable
    [commandBuffer presentDrawable:self.currentDrawable];
    
    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];

}


- (void)_drawCapturedImageWithCommandEncoder:(id<MTLRenderCommandEncoder>)renderEncoder{
    if (_capturedImageTextureYRef == nil || _capturedImageTextureCbCrRef == nil) {
        //NSLog(@"Have not obtained image");
        return;
    }
    
    // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
    [renderEncoder pushDebugGroup:@"MetalCamCapturedImage"];
    
    // Set render command encoder state
    [renderEncoder setCullMode:MTLCullModeNone];
    [renderEncoder setRenderPipelineState:_capturedImagePipelineState];
    [renderEncoder setDepthStencilState:_capturedImageDepthState];
    
    // Set mesh's vertex buffers
    [renderEncoder setVertexBuffer:_imagePlaneVertexBuffer offset:0 atIndex:kBufferIndexMeshPositions];
    
    // Set any textures read/sampled from our render pipeline
    [renderEncoder setFragmentTexture:CVMetalTextureGetTexture(_capturedImageTextureYRef) atIndex:kTextureIndexY];
    [renderEncoder setFragmentTexture:CVMetalTextureGetTexture(_capturedImageTextureCbCrRef) atIndex:kTextureIndexCbCr];
    
    // Draw each submesh of our mesh
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    
    [renderEncoder popDebugGroup];

}


- (CVMetalTextureRef)_createTextureFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                      pixelFormat:(MTLPixelFormat)pixelFormat
                                       planeIndex:(NSInteger)planeIndex {
    
    // 입력 검증
    if (!pixelBuffer || !_capturedImageTextureCache) {
        NSLog(@"Invalid input: pixelBuffer or texture cache is nil");
        return nil;
    }
    
    // 플레인 인덱스 검증
    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    if (planeIndex >= planeCount) {
        NSLog(@"Invalid plane index: %ld, available planes: %zu", (long)planeIndex, planeCount);
        return nil;
    }
    
    const size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex);
    const size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex);
    
    // 크기 검증
    if (width == 0 || height == 0) {
//        NSLog(@"Invalid texture dimensions: %zu x %zu", width, height);
        return nil;
    }
    
    CVMetalTextureRef mtlTextureRef = nil;
    CVReturn status = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,  // NULL 대신 명시적으로 지정
        _capturedImageTextureCache,
        pixelBuffer,
        NULL,
        pixelFormat,
        width,
        height,
        planeIndex,
        &mtlTextureRef
    );
    
    if (status != kCVReturnSuccess) {
//        NSLog(@"Failed to create texture from pixel buffer. CVReturn: %d", status);
        // 💥 버그 수정: mtlTextureRef가 nil일 때 release 하면 안됨
        if (mtlTextureRef) {
            CFRelease(mtlTextureRef);  // CVBufferRelease -> CFRelease
            mtlTextureRef = nil;
        }
        return nil;
    }
    
    // 성공적으로 생성된 경우 텍스처 정보 로그
    if (mtlTextureRef) {
        id<MTLTexture> texture = CVMetalTextureGetTexture(mtlTextureRef);
//        NSLog(@"Created texture: %zu x %zu, format: %lu",
//              texture.width, texture.height, (unsigned long)texture.pixelFormat);
    }
    
    return mtlTextureRef;  // 호출자가 CFRelease 해야 함
}

- (void) _updateImagePlaneWithFrame{
    
    if(_session.currentFrame != nil){
        
        // Update the texture coordinates of our image plane to aspect fill the viewport
        CGAffineTransform displayToCameraTransform = CGAffineTransformInvert([_session.currentFrame displayTransformForOrientation:orientation viewportSize:_viewport.size]);
        
        
        // TODO - example code is fine but here I have to cast? :/
        float *vertexData = (float*)[_imagePlaneVertexBuffer contents];
        
        for (NSInteger index = 0; index < 4; index++) {
            NSInteger textureCoordIndex = 4 * index + 2;
            CGPoint textureCoord = CGPointMake(kImagePlaneVertexData[textureCoordIndex], kImagePlaneVertexData[textureCoordIndex + 1]);
            CGPoint transformedCoord = CGPointApplyAffineTransform(textureCoord, displayToCameraTransform);
            vertexData[textureCoordIndex] = transformedCoord.x;
            vertexData[textureCoordIndex + 1] = transformedCoord.y;
        }
    }

}

- (void) _updateCameraImage {
    
    if(_session.currentFrame){
        // Create two textures (Y and CbCr) from the provided frame's captured image
        CVPixelBufferRef pixelBuffer = _session.currentFrame.capturedImage;
        
#if defined(__IPHONE_13_0)
        depthTextureGLES = [self convertFromPixelBufferToOpenGL:_session.currentFrame.estimatedDepthData _videoTextureCache:_videoTextureCache];
#endif
        
        CVBufferRelease(_capturedImageTextureYRef);
        CVBufferRelease(_capturedImageTextureCbCrRef);
        _capturedImageTextureYRef = [self _createTextureFromPixelBuffer:pixelBuffer pixelFormat:MTLPixelFormatR8Unorm planeIndex:0];
        _capturedImageTextureCbCrRef = [self _createTextureFromPixelBuffer:pixelBuffer pixelFormat:MTLPixelFormatRG8Unorm planeIndex:1];
        
    }
    
}

- (void) loadMetal {

    self._inFlightSemaphore = dispatch_semaphore_create(kMaxBuffersInFlight);
    
    self.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.sampleCount = 1;
    
    for(int i = 0; i < AAPLNumInteropFormats; i++) {
        if(self.colorPixelFormat == AAPLInteropFormatTable[i].mtlFormat) {
            formatInfo = AAPLInteropFormatTable[i];
         
        }
    }
    
    // Create a vertex buffer with our image plane vertex data.
    _imagePlaneVertexBuffer = [self.device newBufferWithBytes:&kImagePlaneVertexData length:sizeof(kImagePlaneVertexData) options:MTLResourceCPUCacheModeDefaultCache];
    
    _imagePlaneVertexBuffer.label = @"MetalCamPlaneVertexBuffer";
    
    // Load all the shader files with a metal file extension in the project
    // NOTE - this line will throw an exception if you don't have a .metal file as part of your compiled sources.
    id <MTLLibrary> defaultLibrary = [self.device newDefaultLibrary];
    
    id <MTLFunction> capturedImageVertexFunction = [defaultLibrary newFunctionWithName:@"capturedImageVertexTransform"];
    id <MTLFunction> capturedImageFragmentFunction = [defaultLibrary newFunctionWithName:@"capturedImageFragmentShader"];
    
    // Create a vertex descriptor for our image plane vertex buffer
    MTLVertexDescriptor *imagePlaneVertexDescriptor = [[MTLVertexDescriptor alloc] init];
    
    // build camera image plane
    // Positions.
    imagePlaneVertexDescriptor.attributes[kVertexAttributePosition].format = MTLVertexFormatFloat2;
    imagePlaneVertexDescriptor.attributes[kVertexAttributePosition].offset = 0;
    imagePlaneVertexDescriptor.attributes[kVertexAttributePosition].bufferIndex = kBufferIndexMeshPositions;
    
    // Texture coordinates.
    imagePlaneVertexDescriptor.attributes[kVertexAttributeTexcoord].format = MTLVertexFormatFloat2;
    imagePlaneVertexDescriptor.attributes[kVertexAttributeTexcoord].offset = 8;
    imagePlaneVertexDescriptor.attributes[kVertexAttributeTexcoord].bufferIndex = kBufferIndexMeshPositions;
    
    // Position Buffer Layout
    imagePlaneVertexDescriptor.layouts[kBufferIndexMeshPositions].stride = 16;
    imagePlaneVertexDescriptor.layouts[kBufferIndexMeshPositions].stepRate = 1;
    imagePlaneVertexDescriptor.layouts[kBufferIndexMeshPositions].stepFunction = MTLVertexStepFunctionPerVertex;
    
    
    // Create a pipeline state for rendering the captured image
    MTLRenderPipelineDescriptor *capturedImagePipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    capturedImagePipelineStateDescriptor.label = @"MetalCamImagePipeline";
    capturedImagePipelineStateDescriptor.sampleCount = self.sampleCount;
    capturedImagePipelineStateDescriptor.vertexFunction = capturedImageVertexFunction;
    capturedImagePipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction;
    capturedImagePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor;
    capturedImagePipelineStateDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;

    capturedImagePipelineStateDescriptor.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
    capturedImagePipelineStateDescriptor.stencilAttachmentPixelFormat = self.depthStencilPixelFormat;
    
    NSError *error = nil;
    _capturedImagePipelineState = [self.device newRenderPipelineStateWithDescriptor:capturedImagePipelineStateDescriptor error:&error];
    if (!_capturedImagePipelineState) {
        NSLog(@"Failed to created captured image pipeline state, error %@", error);
    }
    // do stencil setup
    // TODO this might not be needed in this case.
    MTLDepthStencilDescriptor *capturedImageDepthStateDescriptor = [[MTLDepthStencilDescriptor alloc] init];
    capturedImageDepthStateDescriptor.depthCompareFunction = MTLCompareFunctionAlways;
    capturedImageDepthStateDescriptor.depthWriteEnabled = NO;
    _capturedImageDepthState = [self.device newDepthStencilStateWithDescriptor:capturedImageDepthStateDescriptor];
    
    // initialize image cache
    CVMetalTextureCacheCreate(NULL, NULL, self.device, NULL, &_capturedImageTextureCache);
    
    // Create the command queue
    _commandQueue = [self.device newCommandQueue];
    
    // by default - there is no OpenGL compatibility so set pixel buffer flag to YES to
    // stop initialization.
    pixelBufferBuilt = YES;
    
    [self _setupTextures];
}

// =========== OPENGL COMPATIBILTY =========== //

#define OPENGL_MAX_TEXTURE_SIZE 4096

-(void) _setupTextures {
    /**
     TODO width/height values are currently a bit fudged. Probably need to figure out better solution
     
     Figuring out the pixelBuffer size to get an accurate representation from the Metal frame.
     For some reason - default image is really zoomed in compared to when using the MTKView on it's own.
     Making the sharedPixelBuffer size to be larger fixes the issue, the problem now is coming up
     with an accurate value.
     
     Multiplying the bounds of the screen by the scale doesn't work oddly enough, it results in an
     error during OpenGL texture creation due to the resulting height being larger than the max texture size of 4096.
     
     Multiplying the bounds by 2 seems to do the trick though it's unclear if it's accurate or not at the moment.
     
     Testing results. Note all values are divided by 2
     1. when using scale - width is 1620 and height is 2880
     
     2. when using nativeScale - 1408 and height is 2504
     
     3. no scaling(note values are multiplied by 2 here) - Width is 2160 and height is 3840
     
     Taking
     <full frame width * scale> - <native width> and <full frame height * scale> - <native height> seems
     to be the best solution.
     
     */
    // note that imageResolution is returned in a way as if the camera were in landscape mode so you may need to reverse values. Also note that this is not updated automatically, so probably gonna stick with native bounds of screen.
    //CGSize bounds = _session.configuration.videoFormat.imageResolution;
    CGRect screenBounds = [[UIScreen mainScreen] nativeBounds];
    // this is probably a more reasonable approach.
    auto width = self.currentDrawable.texture.width - screenBounds.size.width;
    auto height = self.currentDrawable.texture.height - screenBounds.size.height;

    width = (width > OPENGL_MAX_TEXTURE_SIZE) ? OPENGL_MAX_TEXTURE_SIZE : width;
    height = (height > OPENGL_MAX_TEXTURE_SIZE) ? OPENGL_MAX_TEXTURE_SIZE : height;

    // NSLog(@"Width is %i and height is %i",width,height);
    /**
     Setup some things here. We do it in an update loop to ensure that we get an
     image as close as possible to what the camera is seeing, the MTKView's currentDrawable isn't
     available until the loop starts.
     */
    // setup the shared pixel buffer so we can send this to OpenGL
    CVReturn cvret = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,height,
                                         formatInfo.cvPixelFormat,
                                         (__bridge CFDictionaryRef)cvBufferProperties,
                                         &_sharedPixelBuffer);
    
    if(cvret != kCVReturnSuccess)
    {
        assert(!"Failed to create shared opengl pixel buffer");
    }
    
    pixelBufferBuilt = YES;
    
    // set the region we want to capture in the Metal frame
    captureRegion = MTLRegionMake2D(0, 0, width, height);
    
    
    // 1. Create a Metal Core Video texture cache from the pixel buffer.
    cvret = CVMetalTextureCacheCreate(
                                      kCFAllocatorDefault,
                                      nil,
                                      self.device,
                                      nil,
                                      &_combinedCameraTextureCache);
    if(cvret != kCVReturnSuccess)
    {
        assert(!"Issue initiailizing metal texture cache for combined image.");
    }
    // 2. Create a CoreVideo pixel buffer backed Metal texture image from the texture cache.
    cvret = CVMetalTextureCacheCreateTextureFromImage(
                                                      kCFAllocatorDefault,
                                                      _combinedCameraTextureCache,
                                                      _sharedPixelBuffer, nil,
                                                      formatInfo.mtlFormat,
                                                      width, height,
                                                      0,
                                                      &_cameraImage);
    if(cvret != kCVReturnSuccess)
    {
        assert(!"Failed to create Metal texture cache");
    }
    
    _cameraTexture = CVMetalTextureGetTexture(_cameraImage);
    
#if defined(__IPHONE_13_0)
    //=================================================================================
    // create a pixel buffer with the size and pixel format corresponding to :
    // MTLTexture Alpha --> with (full resolution) : 1920 x 1440
    // MTLTexture Alpha --> with format (10) MTLPixelFormatR8Unorm corresponding to kCVPixelFormatType_OneComponent8 for  pixel buffer
    //=================================================================================

    cvret = CVPixelBufferCreate(kCFAllocatorDefault,
                                         1920, 1440,
                                         kCVPixelFormatType_OneComponent8,
                                         (__bridge CFDictionaryRef)cvBufferProperties,
                                         &pixel_bufferAlphaMatte);

    if(cvret != kCVReturnSuccess)
    {
        assert(!"Failed to create shared opengl pixel_bufferAlpha");
    }

    //=================================================================================
    // create a pixel buffer with the size and pixel format corresponding to :
    // MTLTexture Depth --> with (full resolution) : 256 x 192
    // MTLTexture Depth --> with format (25) MTLPixelFormatR16Float corresponding to kCVPixelFormatType_OneComponent16Half for  pixel buffer
    //=================================================================================
    cvret = CVPixelBufferCreate(kCFAllocatorDefault,
                                         512, 192,
                                         kCVPixelFormatType_OneComponent16Half,
                                         (__bridge CFDictionaryRef)cvBufferProperties,
                                         &pixel_bufferDepthMatte);

    if(cvret != kCVReturnSuccess)
    {
        assert(!"Failed to create shared opengl pixel_bufferDepth");
    }

    //=================================================================================

    
    [self _initMatteTexture];
#endif
    
}

- (CVOpenGLESTextureRef) getConvertedTexture{
    return openglTexture;
}
#if defined(__IPHONE_13_0)
// return
- (CVOpenGLESTextureRef) getConvertedTextureMatteAlpha{
    return alphaTextureMatteGLES;
}

- (CVOpenGLESTextureRef) getConvertedTextureMatteDepth{
    return depthTextureMatteGLES;
}

- (CVOpenGLESTextureRef) getConvertedTextureDepth{
    return depthTextureGLES;
}
- (CGAffineTransform) getAffineCameraTransform
{
    return CGAffineTransformInvert([_session.currentFrame displayTransformForOrientation:orientation viewportSize:_viewport.size]);
}
-(void) _initMatteTexture{
    
    matteDepthTexture = [[ARMatteGenerator alloc] initWithDevice: self.device matteResolution: ARMatteResolutionFull];
}
- (void) _updateMatteTextures:(id<MTLCommandBuffer>) commandBuffer {
    if(self.currentDrawable && _session.currentFrame.capturedImage){
        
        dilatedDepthTexture = [matteDepthTexture generateDilatedDepthFromFrame:_session.currentFrame commandBuffer:commandBuffer];
        alphaTexture = [matteDepthTexture  generateMatteFromFrame:_session.currentFrame commandBuffer:commandBuffer];
        
        alphaTextureMatteGLES = [self convertFromMTLToOpenGL: alphaTexture pixel_buffer:pixel_bufferAlphaMatte _videoTextureCache:_videoTextureCache];
        depthTextureMatteGLES = [self convertFromMTLToOpenGL: dilatedDepthTexture pixel_buffer:pixel_bufferDepthMatte _videoTextureCache:_videoTextureCache];
        

    }else{
        return;
    }
}

#endif

- (void) _updateOpenGLTexture{
    
    if(self.currentDrawable && _session.currentFrame.capturedImage){
        
        
        CVPixelBufferLockBaseAddress(_sharedPixelBuffer, 0);
      
        // convert shared pixel buffer into an OpenGL texture
        openglTexture = [self convertToOpenGLTexture:_sharedPixelBuffer];
        
        // correct wrapping and filtering
        glBindTexture(CVOpenGLESTextureGetTarget(openglTexture), CVOpenGLESTextureGetName(openglTexture));
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER,GL_LINEAR);
        glBindTexture(CVOpenGLESTextureGetTarget(openglTexture), 0);
        
        CVPixelBufferUnlockBaseAddress(_sharedPixelBuffer, 0);
        
    }
    

}
- (void) setupOpenGLCompatibility:(CVEAGLContext) eaglContext{
    // initialize video texture cache
    CVReturn err = CVOpenGLESTextureCacheCreate(
                                                kCFAllocatorDefault,
                                                nil,
                                                eaglContext,
                                                nil,
                                                &_videoTextureCache);
    if (err){
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
    }
    
    openglMode = YES;
    pixelBufferBuilt = NO;
  
}

- (CVPixelBufferRef) getSharedPixelbuffer{
    return _sharedPixelBuffer;
}
- (CVOpenGLESTextureRef) convertToOpenGLTexture:(CVPixelBufferRef) pixelBuffer {
    CVOpenGLESTextureRef texture = NULL;
    
    CVPixelBufferLockBaseAddress(_sharedPixelBuffer, 0);
    
    CVReturn err = noErr;
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _videoTextureCache,
                                                       _sharedPixelBuffer,
                                                       nil,
                                                       GL_TEXTURE_2D,
                                                       formatInfo.glInternalFormat,
                                                       CVPixelBufferGetWidth(_sharedPixelBuffer),
                                                       CVPixelBufferGetHeight(_sharedPixelBuffer),
                                                       formatInfo.glFormat,
                                                       formatInfo.glType,
                                                       0,
                                                       &texture);
    
    if (err != kCVReturnSuccess) {
        CVBufferRelease(texture);

        //NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        if(err == kCVReturnInvalidPixelFormat){
            NSLog(@"Invalid pixel format");
        }
        
        if(err == kCVReturnInvalidPixelBufferAttributes){
            NSLog(@"Invalid pixel buffer attributes");
        }
        
        if(err == kCVReturnInvalidSize){
            NSLog(@"invalid size");
        }
        
        if(err == kCVReturnPixelBufferNotOpenGLCompatible){
            NSLog(@"not opengl compatible");
        }
        
    }
    
    // clear texture cache
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
    CVPixelBufferUnlockBaseAddress(_sharedPixelBuffer, 0);
    
    return texture;
    
}

- (CVOpenGLESTextureRef) convertFromMTLToOpenGL:(id<MTLTexture>) texture  pixel_buffer:(CVPixelBufferRef)pixel_buffer _videoTextureCache:(CVOpenGLESTextureCacheRef)vidTextureCache
{
     int width = (int) texture.width;
     int height = (int) texture.height;
//     MTLPixelFormat texPixelFormat = texture.pixelFormat;
//    NSLog(@"texture PixelFormat : %lu width : %d height : %d", (unsigned long)texPixelFormat, width, height);
    

     CVPixelBufferLockBaseAddress(pixel_buffer, 0);
     void * CV_NULLABLE pixelBufferBaseAdress = CVPixelBufferGetBaseAddress(pixel_buffer);
     size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixel_buffer);

      [texture getBytes:pixelBufferBaseAdress
                         bytesPerRow:bytesPerRow
                         fromRegion:MTLRegionMake2D(0, 0, width, height)
                         mipmapLevel:0];


     size_t w = CVPixelBufferGetWidth(pixel_buffer);
     size_t h = CVPixelBufferGetHeight(pixel_buffer);
    
    CVOpenGLESTextureRef texGLES = nil;

     CVReturn err = noErr;
     err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                     vidTextureCache,
                                                     pixel_buffer,
                                                     nil,
                                                     GLenum(GL_TEXTURE_2D),
                                                     GLint(GL_LUMINANCE),
                                                     w,
                                                     h,
                                                     GLenum(GL_LUMINANCE),
                                                     GLenum(GL_UNSIGNED_BYTE),
                                                     0,
                                                     &texGLES);


     if (err != kCVReturnSuccess) {
         CVBufferRelease(pixel_buffer);
//         NSLog(@"error on CVOpenGLESTextureCacheCreateTextureFromImage");
     }

     CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
     CVOpenGLESTextureCacheFlush(vidTextureCache, 0);
    

    // correct wrapping and filtering
    glBindTexture(CVOpenGLESTextureGetTarget(texGLES), CVOpenGLESTextureGetName(texGLES));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    glBindTexture(CVOpenGLESTextureGetTarget(texGLES), 0);
    
    return texGLES;
}

- (CVOpenGLESTextureRef) convertFromPixelBufferToOpenGL:(CVPixelBufferRef)pixel_buffer _videoTextureCache:(CVOpenGLESTextureCacheRef)vidTextureCache
{

    CVOpenGLESTextureRef texGLES = nil;
    size_t w = CVPixelBufferGetWidth(pixel_buffer);
    size_t h = CVPixelBufferGetHeight(pixel_buffer);
    CVReturn err = noErr;

    CVPixelBufferLockBaseAddress(pixel_buffer, 0);


    err = CVOpenGLESTextureCacheCreateTextureFromImage( kCFAllocatorDefault,
                                                        _videoTextureCache,
                                                        pixel_buffer,
                                                        nil,
                                                        GLenum(GL_TEXTURE_2D),
                                                        GLint(GL_RGBA),
                                                        w,
                                                        h,
                                                        GLenum(GL_BGRA_EXT),
                                                        GLenum(GL_UNSIGNED_BYTE),
                                                        0,
                                                        &texGLES);


    if (err != kCVReturnSuccess) {
//        NSLog(@"not working");
    }else{
    //            NSLog(@"working fine");
    }

    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);

    // correct wrapping and filtering
    glBindTexture(CVOpenGLESTextureGetTarget(texGLES), CVOpenGLESTextureGetName(texGLES));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    glBindTexture(CVOpenGLESTextureGetTarget(texGLES), 0);

    return texGLES;
}


@end
