//  Copyright (C) 2010-2016 Pierre-Olivier Latour <info@pol-online.net>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#undef __STRICT_ANSI__  // Work around WEBP_INLINE not defined as "inline"

#import <sys/sysctl.h>
#import <webp/decode.h>
#import <ImageIO/ImageIO.h>

#import "ImageDecompression.h"
#import "ImageUtilities.h"

#define __USE_RGBX_JPEG__ 0  // RGB appears a bit faster than RGBX on iPad Mini
#define __USE_RGBA_WEBP__ 0  // RGB appears a bit faster than RGBA on iPad Mini

BOOL IsImageFileExtensionSupported(NSString* extension) {
  return ![extension caseInsensitiveCompare:@"jpg"] || ![extension caseInsensitiveCompare:@"jpeg"] ||
         ![extension caseInsensitiveCompare:@"png"] || ![extension caseInsensitiveCompare:@"gif"] ||
         ![extension caseInsensitiveCompare:@"webp"];
}

static void _ReleaseDataCallback(void* info, const void* data, size_t size) {
  free(info);
}

static CGImageRef _CreateCGImageFromWebPData(NSData* data) {
  static uint32_t cores = 0;
  if (cores == 0) {
    size_t length = sizeof(cores);
    if (sysctlbyname("hw.physicalcpu", &cores, &length, NULL, 0)) {
      cores = 1;
    }
  }
  
  WebPDecoderConfig config;
  WebPInitDecoderConfig(&config);
  VP8StatusCode status = WebPGetFeatures(data.bytes, data.length, &config.input);
  if (status != VP8_STATUS_OK) {
    XLOG_ERROR(@"Failed retrieving WebP image features (%i)", status);
    return NULL;
  }
#if __USE_RGBA_WEBP__
  size_t rowBytes = 4 * config.input.width;
#else
  size_t rowBytes = 3 * config.input.width;
#endif
  if (rowBytes % 16) {
    rowBytes = ((rowBytes / 16) + 1) * 16;
  }
  size_t size = config.input.height * rowBytes;
  void* buffer = malloc(size);
  if (buffer == NULL) {
    XLOG_ERROR(@"Failed allocating memory for WebP buffer");
    return NULL;
  }
  config.options.bypass_filtering = 1;
  config.options.no_fancy_upsampling = 1;
  config.options.use_threads = cores > 1 ? 1 : 0;
#if __USE_RGBA_WEBP__
  config.output.colorspace = MODE_RGBA;
#else
  config.output.colorspace = MODE_RGB;
#endif
  config.output.is_external_memory = 1;
  config.output.u.RGBA.rgba = buffer;
  config.output.u.RGBA.stride = rowBytes;
  config.output.u.RGBA.size = size;
  status = WebPDecode(data.bytes, data.length, &config);
  if (status != VP8_STATUS_OK) {
    XLOG_ERROR(@"Failed decoding WebP image (%i)", status);
    free(buffer);
    return NULL;
  }
  
  CGDataProviderRef provider = CGDataProviderCreateWithData(buffer, buffer, size, _ReleaseDataCallback);
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
#if __USE_RGBA_WEBP__
  CGImageRef imageRef = CGImageCreate(config.input.width, config.input.height, 8, 32, rowBytes, colorspace, kCGImageAlphaNoneSkipLast, provider, NULL, true, kCGRenderingIntentDefault);
#else
  CGImageRef imageRef = CGImageCreate(config.input.width, config.input.height, 8, 24, rowBytes, colorspace, kCGImageAlphaNone, provider, NULL, true, kCGRenderingIntentDefault);
#endif
  CGColorSpaceRelease(colorspace);
  CGDataProviderRelease(provider);
  
  return imageRef;
}

static CGImageRef _CreateCGImageFromData(NSData* data) {
  CGImageRef imageRef = NULL;
  CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
  if (source) {
    imageRef = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
  }
  return imageRef;
}

CGImageRef CreateCGImageFromFileData(NSData* data, NSString* extension, CGSize targetSize, BOOL thumbnailMode) {
  CFTimeInterval time = CFAbsoluteTimeGetCurrent();
  CGImageRef imageRef = NULL;
  if (![extension caseInsensitiveCompare:@"webp"]) {
    imageRef = _CreateCGImageFromWebPData(data);
  } else {
    imageRef = _CreateCGImageFromData(data);
  }
  if (imageRef) {
    if (thumbnailMode || (CGImageGetWidth(imageRef) > (size_t)targetSize.width) || (CGImageGetHeight(imageRef) > (size_t)targetSize.height)) {
      CGImageRef scaledImageRef = CreateScaledImage(imageRef, targetSize, thumbnailMode ? kImageScalingMode_AspectFill : kImageScalingMode_AspectFit, [[UIColor blackColor] CGColor]);
      if (scaledImageRef) {
        XLOG_VERBOSE(@"Decompressed '%@' image of %ix%i pixels and rescaled to %ix%i pixels in %.3f seconds", [extension lowercaseString],
                     (int)CGImageGetWidth(imageRef), (int)CGImageGetHeight(imageRef), (int)CGImageGetWidth(scaledImageRef), (int)CGImageGetHeight(scaledImageRef), CFAbsoluteTimeGetCurrent() - time);
      }
      CGImageRelease(imageRef);
      imageRef = scaledImageRef;
    } else {
      XLOG_VERBOSE(@"Decompressed '%@' image of %ix%i pixels in %.3f seconds", [extension lowercaseString],
                   (int)CGImageGetWidth(imageRef), (int)CGImageGetHeight(imageRef), CFAbsoluteTimeGetCurrent() - time);
    }
  }
  return imageRef;
}

CGImageRef CreateCGImageFromPDFPage(CGPDFPageRef page, CGSize targetSize, BOOL thumbnailMode) {
  // Render at 2x resolution to ensure good antialiasing
  if (thumbnailMode) {
    targetSize.width *= 2.0;
    targetSize.height *= 2.0;
  }
  return CreateRenderedPDFPage(page, targetSize, thumbnailMode ? kImageScalingMode_AspectFill : kImageScalingMode_AspectFit, [[UIColor whiteColor] CGColor]);
}
