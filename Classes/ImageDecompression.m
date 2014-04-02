//  Copyright (C) 2010-2014 Pierre-Olivier Latour <info@pol-online.net>
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
#import <jerror.h>
#import <jpeglib.h>
#import <webp/decode.h>
#import <ImageIO/ImageIO.h>

#import "ImageDecompression.h"
#import "ImageUtilities.h"
#import "Logging.h"

#define __USE_RGBX_JPEG__ 0  // RGB appears a bit faster than RGBX on iPad Mini
#define __USE_RGBA_WEBP__ 0  // RGB appears a bit faster than RGBA on iPad Mini

typedef struct {
  struct jpeg_error_mgr error_mgr;
  jmp_buf jmp_buffer;
} ErrorManager;

// Replace default implementation to log error and use longjmp() instead of simply calling exit()
static void _ErrorExit(j_common_ptr cinfo) {
  ErrorManager* errorManager = (ErrorManager*)cinfo->err;
  
  char buffer[JMSG_LENGTH_MAX];
  (*errorManager->error_mgr.format_message)(cinfo, buffer);
  LOG_ERROR(@"libjpeg error (%i): %s", errorManager->error_mgr.msg_code, buffer);
  
  if (cinfo->err->msg_code != JERR_UNKNOWN_MARKER) {
    longjmp(errorManager->jmp_buffer, 1);
  }
}

static void _EmitMessage(j_common_ptr cinfo, int msg_level) {
  ErrorManager* errorManager = (ErrorManager*)cinfo->err;
  
  if (msg_level < 0) {  // Indicates a corrupt-data warning
    char buffer[JMSG_LENGTH_MAX];
    (*errorManager->error_mgr.format_message)(cinfo, buffer);
    LOG_WARNING(@"libjpeg warning (%i): %s", errorManager->error_mgr.msg_code, buffer);
    if ((errorManager->error_mgr.msg_code == JWRN_EXTRANEOUS_DATA) && (errorManager->error_mgr.msg_parm.i[1] == 0xD9)) {
      // Extraneous bytes before EOI marker should be acceptable (e.g. Sony Ericsson P990i)
    } else {
      longjmp(errorManager->jmp_buffer, 1);  // Abort on corrupt-data
    }
  } else if (msg_level == 0) {  // Indicates an advisory message
    char buffer[JMSG_LENGTH_MAX];
    (*errorManager->error_mgr.format_message)(cinfo, buffer);
    LOG_INFO(@"libjpeg message (%i): %s", errorManager->error_mgr.msg_code, buffer);
  }
}

BOOL IsImageFileExtensionSupported(NSString* extension) {
  return ![extension caseInsensitiveCompare:@"jpg"] || ![extension caseInsensitiveCompare:@"jpeg"] ||
         ![extension caseInsensitiveCompare:@"png"] || ![extension caseInsensitiveCompare:@"gif"] ||
         ![extension caseInsensitiveCompare:@"webp"];
}

static void _ReleaseDataCallback(void* info, const void* data, size_t size) {
  free(info);
}

static CGImageRef _CreateCGImageFromJPEGData(NSData* data, CGSize targetSize, BOOL fillMode) {
  void* buffer = NULL;
  struct jpeg_decompress_struct dinfo;
  ErrorManager errorManager;
  jpeg_create_decompress(&dinfo);
  dinfo.err = jpeg_std_error(&errorManager.error_mgr);
  errorManager.error_mgr.error_exit = _ErrorExit;
  errorManager.error_mgr.emit_message = _EmitMessage;
  if (setjmp(errorManager.jmp_buffer)) {
    if (buffer) {
      free(buffer);
    }
    jpeg_destroy_decompress(&dinfo);
    return NULL;
  }
  jpeg_mem_src(&dinfo, (unsigned char*)data.bytes, data.length);
  jpeg_read_header(&dinfo, true);  // This sets dinfo.scale_num and dinfo.scale_denom to 1
  
  size_t width = dinfo.image_width;
  size_t height = dinfo.image_height;
  unsigned int target_size = MAX(targetSize.width, targetSize.height);
  if (fillMode) {
    unsigned int min_size = MIN(width, height);
    if (min_size > target_size) {
      dinfo.scale_denom = MIN(1 << (unsigned int)log2f((float)min_size / target_size), 8);
    }
  } else {
    unsigned int max_size = MAX(width, height);
    if (max_size > target_size) {
      dinfo.scale_denom = MIN(1 << (unsigned int)log2f((float)max_size / target_size), 8);
    }
  }
  jpeg_calc_output_dimensions(&dinfo);
  
  size_t rowBytes = 4 * dinfo.output_width;
  if (rowBytes % 16) {
    rowBytes = ((rowBytes / 16) + 1) * 16;
  }
  size_t size = dinfo.output_height * rowBytes;
  buffer = malloc(size);
  if (buffer == NULL) {
    LOG_ERROR(@"Failed allocating memory for JPEG buffer");
    jpeg_destroy_decompress(&dinfo);
    return NULL;
  }
  dinfo.dct_method = JDCT_IFAST;
#if __USE_RGBX_JPEG__
  dinfo.out_color_space = JCS_EXT_RGBX;
#else
  dinfo.out_color_space = JCS_RGB;
#endif
  jpeg_start_decompress(&dinfo);
  JDIMENSION scanline = 0;
  unsigned char* base_address = (unsigned char*)buffer;
  while (scanline < dinfo.output_height) {
    JDIMENSION lines = jpeg_read_scanlines(&dinfo, (JSAMPARRAY)&base_address, dinfo.rec_outbuf_height);
    scanline += lines;
    base_address += lines * rowBytes;
  }
  jpeg_finish_decompress(&dinfo);
  jpeg_destroy_decompress(&dinfo);
  
  CGDataProviderRef provider = CGDataProviderCreateWithData(buffer, buffer, size, _ReleaseDataCallback);
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
#if __USE_RGBX_JPEG__
  CGImageRef imageRef = CGImageCreate(dinfo.output_width, dinfo.output_height, 8, 32, rowBytes, colorspace, kCGImageAlphaNoneSkipLast, provider, NULL, true, kCGRenderingIntentDefault);
#else
  CGImageRef imageRef = CGImageCreate(dinfo.output_width, dinfo.output_height, 8, 24, rowBytes, colorspace, kCGImageAlphaNone, provider, NULL, true, kCGRenderingIntentDefault);
#endif
  CGColorSpaceRelease(colorspace);
  CGDataProviderRelease(provider);
  
  return imageRef;
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
    LOG_ERROR(@"Failed retrieving WebP image features (%i)", status);
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
    LOG_ERROR(@"Failed allocating memory for WebP buffer");
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
    LOG_ERROR(@"Failed decoding WebP image (%i)", status);
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
  if (![extension caseInsensitiveCompare:@"jpg"] || ![extension caseInsensitiveCompare:@"jpeg"]) {
    imageRef = _CreateCGImageFromJPEGData(data, targetSize, thumbnailMode);
  } else if (![extension caseInsensitiveCompare:@"webp"]) {
    imageRef = _CreateCGImageFromWebPData(data);
  } else {
    imageRef = _CreateCGImageFromData(data);
  }
  if (imageRef) {
    if (thumbnailMode || (CGImageGetWidth(imageRef) > (size_t)targetSize.width) || (CGImageGetHeight(imageRef) > (size_t)targetSize.height)) {
      CGImageRef scaledImageRef = CreateScaledImage(imageRef, targetSize, thumbnailMode ? kImageScalingMode_AspectFill : kImageScalingMode_AspectFit, [[UIColor blackColor] CGColor]);
      if (scaledImageRef) {
        LOG_VERBOSE(@"Decompressed '%@' image of %ix%i pixels and rescaled to %ix%i pixels in %.3f seconds", [extension lowercaseString],
                    CGImageGetWidth(imageRef), CGImageGetHeight(imageRef), CGImageGetWidth(scaledImageRef), CGImageGetHeight(scaledImageRef), CFAbsoluteTimeGetCurrent() - time);
      }
      CGImageRelease(imageRef);
      imageRef = scaledImageRef;
    } else {
      LOG_VERBOSE(@"Decompressed '%@' image of %ix%i pixels in %.3f seconds", [extension lowercaseString],
                  CGImageGetWidth(imageRef), CGImageGetHeight(imageRef), CFAbsoluteTimeGetCurrent() - time);
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
