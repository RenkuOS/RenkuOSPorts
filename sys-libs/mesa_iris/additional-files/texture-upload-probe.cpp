// SPDX-License-Identifier: MIT
#define GL_GLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <GL/gl.h>
#include <GL/glext.h>
#include <Application.h>
#include <Bitmap.h>
#include <stdint.h>
#include <stdio.h>
class BitmapHook {
public:
 virtual ~BitmapHook() {};
 virtual void GetSize(uint32_t &w,uint32_t &h)=0;
 virtual BBitmap *SetBitmap(BBitmap *bmp)=0;
};
class Hook : public BitmapHook {
 BBitmap *bitmap=nullptr;
public:
 ~Hook(){delete bitmap;}
 void GetSize(uint32_t&w,uint32_t&h) override {w=32;h=32;}
 BBitmap *SetBitmap(BBitmap*b) override {BBitmap*old=bitmap;bitmap=b;return old;}
};
int main(){
 BApplication app("application/x-vnd.intel-gen9-texture-upload-test");Hook hook;
 EGLDisplay d=eglGetDisplay(EGL_DEFAULT_DISPLAY);EGLint major,minor,n;
 if(!eglInitialize(d,&major,&minor)||!eglBindAPI(EGL_OPENGL_API))return 1;
 EGLint attrs[]={EGL_SURFACE_TYPE,EGL_WINDOW_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_BIT,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_NONE};
 EGLConfig cfg;if(!eglChooseConfig(d,attrs,&cfg,1,&n)||n!=1)return 2;
 EGLSurface s=eglCreateWindowSurface(d,cfg,(EGLNativeWindowType)&hook,nullptr);
 EGLContext a=eglCreateContext(d,cfg,EGL_NO_CONTEXT,nullptr),b=eglCreateContext(d,cfg,EGL_NO_CONTEXT,nullptr);
 if(s==EGL_NO_SURFACE||a==EGL_NO_CONTEXT||b==EGL_NO_CONTEXT||!eglMakeCurrent(d,s,s,a))return 3;
 printf("renderer=%s; two live contexts\n",glGetString(GL_RENDERER));fflush(stdout);
 GLuint tex,fbo;glGenTextures(1,&tex);glBindTexture(GL_TEXTURE_2D,tex);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
 glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,4,4,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);
 glGenFramebuffers(1,&fbo);glBindFramebuffer(GL_FRAMEBUFFER,fbo);
 glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex,0);
 if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE)return 4;
 unsigned char image[64],readback[64];
 for(int frame=0;frame<32;++frame){
  for(int p=0;p<16;++p){image[p*4]=frame*7;image[p*4+1]=255-frame*5;image[p*4+2]=frame*3;image[p*4+3]=255;}
  glTexSubImage2D(GL_TEXTURE_2D,0,0,0,4,4,GL_BGRA,GL_UNSIGNED_BYTE,image);
  glReadPixels(0,0,4,4,GL_RGBA,GL_UNSIGNED_BYTE,readback);
  if(glGetError()!=GL_NO_ERROR)return 5;
  for(int p=0;p<64;++p)if(image[(p%4==0)?p+2:(p%4==2)?p-2:p]!=readback[p]){printf("FAIL frame=%d byte=%d\n",frame,p);return 6;}
 }
 glDeleteFramebuffers(1,&fbo);glDeleteTextures(1,&tex);
 eglMakeCurrent(d,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
 eglDestroyContext(d,b);eglDestroyContext(d,a);eglDestroySurface(d,s);eglTerminate(d);
 puts("PASS: 32 texture uploads with two live contexts");return 0;
}
