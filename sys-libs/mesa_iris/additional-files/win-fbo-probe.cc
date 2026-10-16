/*
 * win-fbo-probe - draw IDENTICAL geometry in the SAME EGL context into
 *   (a) an application FBO (read back with glReadPixels), and
 *   (b) the Haiku window/default framebuffer (read back via our BitmapHook).
 * Compares the two to separate "geometry/transform wrong" from
 * "window resource/present wrong".
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>

#include <Application.h>
#include <Bitmap.h>
#include <Rect.h>

#define WIDTH 128
#define HEIGHT 128

static unsigned failures;
static bool clear_only;
static void check_gl(const char *step)
{
	GLenum error;
	while ((error = glGetError()) != GL_NO_ERROR) {
		printf("FAIL %s GL error %#x\n", step, error);
		++failures;
	}
}

static void check_pixels(const unsigned char *buf, int stride, bool bgr, bool top)
{
	const unsigned char colors[4][3] = {{255,0,0}, {0,255,0}, {0,0,255}, {255,255,255}};
	for (int q = 0; q < 4; ++q) {
		int x = (q % 2 ? 3 : 1) * WIDTH / 4;
		int y = (q / 2 ? 3 : 1) * HEIGHT / 4;
		int c = top ? q ^ 2 : q;
		const unsigned char *pixel = buf + y * stride + x * 4;
		unsigned char expected[3];
		for (int k = 0; k < 3; ++k)
			expected[k] = clear_only ? (k == 0 ? 64 : k == 1 ? 128 : 191) : colors[c][k];
		if (pixel[bgr ? 2 : 0] != expected[0] || pixel[1] != expected[1] ||
		    pixel[bgr ? 0 : 2] != expected[2]) {
			printf("FAIL pixel q=%d got RGB=%u,%u,%u want %u,%u,%u\n", q,
				pixel[bgr ? 2 : 0], pixel[1], pixel[bgr ? 0 : 2],
				expected[0], expected[1], expected[2]);
			++failures;
		}
	}
}

/* Must match Mesa's hgl_sw_winsys.h (private header). */
class BitmapHook {
public:
	virtual ~BitmapHook() {};
	virtual void GetSize(uint32_t &width, uint32_t &height) = 0;
	virtual BBitmap *SetBitmap(BBitmap *bmp) = 0;
};

static void
dump_ppm(const char *path, const unsigned char *base, int stride, int w, int h,
	bool flip)
{
	FILE *f = fopen(path, "wb");
	if (!f)
		return;
	fprintf(f, "P6\n%d %d\n255\n", w, h);
	for (int y = 0; y < h; y++) {
		const unsigned char *p = base + (flip ? (h - 1 - y) : y) * stride;
		for (int x = 0; x < w; x++) {
			unsigned char rgb[3] = { p[x * 4 + 2], p[x * 4 + 1], p[x * 4 + 0] };
			fwrite(rgb, 1, 3, f);
		}
	}
	fclose(f);
}

class MyHook : public BitmapHook {
public:
	MyHook() : fCurrent(NULL), fFrames(0) {}
	virtual void GetSize(uint32_t &width, uint32_t &height)
	{
		width = WIDTH;
		height = HEIGHT;
	}
	virtual BBitmap *SetBitmap(BBitmap *bmp)
	{
		BBitmap *old = fCurrent;
		fCurrent = bmp;
		if (bmp != NULL) {
			++fFrames;
			check_pixels((const unsigned char *)bmp->Bits(), bmp->BytesPerRow(), true, true);
			if (fFrames != 1) return old;
			const unsigned char *bits = (const unsigned char *)bmp->Bits();
			printf("WINDOW bitmap samples (BGR), perrow=%d:\n",
				(int)bmp->BytesPerRow());
			const char *name[4] = { "TL", "TR", "BL", "BR" };
			for (int q = 0; q < 4; ++q) {
				int x = (q % 2 ? 3 : 1) * WIDTH / 4;
				int y = (q / 2 ? 3 : 1) * HEIGHT / 4;
				const unsigned char *p =
					bits + y * bmp->BytesPerRow() + x * 4;
				printf("  %s (%d,%d): BGR=%3u,%3u,%3u\n", name[q], x, y,
					p[0], p[1], p[2]);
			}
			dump_ppm("/tmp/winfbo-window.ppm", bits, bmp->BytesPerRow(),
				WIDTH, HEIGHT, false);
		}
		return old;
	}

private:
	BBitmap *fCurrent;
	unsigned fFrames;
};

static void
draw_quads(void)
{
	glViewport(0, 0, WIDTH, HEIGHT);
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(0.0, 1.0, 0.0, 1.0, -1.0, 1.0);
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();

	glClearColor(clear_only ? .25f : 0, clear_only ? .5f : 0, clear_only ? .75f : 0, 1);
	glClear(GL_COLOR_BUFFER_BIT);

	if (clear_only) return;
	glBegin(GL_QUADS);
	glColor3f(1, 0, 0); glVertex2f(0.05f, 0.05f); glVertex2f(0.45f, 0.05f);
	                    glVertex2f(0.45f, 0.45f); glVertex2f(0.05f, 0.45f);
	glColor3f(0, 1, 0); glVertex2f(0.55f, 0.05f); glVertex2f(0.95f, 0.05f);
	                    glVertex2f(0.95f, 0.45f); glVertex2f(0.55f, 0.45f);
	glColor3f(0, 0, 1); glVertex2f(0.05f, 0.55f); glVertex2f(0.45f, 0.55f);
	                    glVertex2f(0.45f, 0.95f); glVertex2f(0.05f, 0.95f);
	glColor3f(1, 1, 1); glVertex2f(0.55f, 0.55f); glVertex2f(0.95f, 0.55f);
	                    glVertex2f(0.95f, 0.95f); glVertex2f(0.55f, 0.95f);
	glEnd();
}

int
main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	BApplication application("application/x-vnd.haiku-win-fbo-probe");
	MyHook hook;
	clear_only = getenv("EGL_HAIKU_CLEARONLY") != NULL;

	EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	EGLint maj = 0, min = 0;
	if (!eglInitialize(dpy, &maj, &min)) {
		printf("eglInitialize failed\n");
		return 1;
	}
	eglBindAPI(EGL_OPENGL_API);

	EGLint ca[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8, EGL_NONE
	};
	EGLConfig cfg = NULL;
	EGLint n = 0;
	if (!eglChooseConfig(dpy, ca, &cfg, 1, &n) || n < 1) {
		printf("eglChooseConfig failed\n");
		return 1;
	}

	EGLSurface s = eglCreateWindowSurface(dpy, cfg,
		(EGLNativeWindowType)(uintptr_t)&hook, NULL);
	if (s == EGL_NO_SURFACE) {
		printf("eglCreateWindowSurface failed 0x%x\n", eglGetError());
		return 1;
	}
	EGLContext c = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, NULL);
	if (!eglMakeCurrent(dpy, s, s, c)) {
		printf("eglMakeCurrent failed 0x%x\n", eglGetError());
		return 1;
	}
	printf("renderer=%s\n", (const char *)glGetString(GL_RENDERER));

	/* ---- (a) identical geometry into application FBOs of various shapes ---- */
	GLuint tex = 0, fbo = 0, rb = 0;
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, WIDTH, HEIGHT, 0, GL_RGBA,
		GL_UNSIGNED_BYTE, NULL);
	glGenFramebuffers(1, &fbo);
	glGenRenderbuffers(1, &rb);
	glBindRenderbuffer(GL_RENDERBUFFER, rb);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, WIDTH, HEIGHT);

	unsigned char *buf = (unsigned char *)malloc(WIDTH * HEIGHT * 4);
	const char *cfgname[4] = { "color-only", "color+Z24S8 test-off",
		"color+Z24S8 test-on", "unused" };
	for (int cfg = 0; cfg < (getenv("EGL_HAIKU_WINONLY") ? 0 : 3); ++cfg) {
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
			GL_TEXTURE_2D, tex, 0);
		if (cfg >= 1)
			glFramebufferRenderbuffer(GL_FRAMEBUFFER,
				GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, rb);
		else
			glFramebufferRenderbuffer(GL_FRAMEBUFFER,
				GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, 0);

		if (cfg == 2) {
			glEnable(GL_DEPTH_TEST);
			glClearDepth(1.0);
			glClear(GL_DEPTH_BUFFER_BIT);
		} else {
			glDisable(GL_DEPTH_TEST);
		}
		draw_quads();
		glFinish();

		check_gl("FBO draw");
		memset(buf, 0xA5, WIDTH * HEIGHT * 4);
		glReadPixels(0, 0, WIDTH, HEIGHT, GL_RGBA, GL_UNSIGNED_BYTE, buf);
		check_gl("FBO read");
		check_pixels(buf, WIDTH * 4, false, false);
		int sx[4] = { WIDTH / 4, 3 * WIDTH / 4, WIDTH / 4, 3 * WIDTH / 4 };
		int sy[4] = { HEIGHT / 4, HEIGHT / 4, 3 * HEIGHT / 4, 3 * HEIGHT / 4 };
		printf("FBO[%s] err=0x%04x samples:", cfgname[cfg],
			(unsigned)glGetError());
		for (int q = 0; q < 4; ++q) {
			unsigned char *p = buf + (sy[q] * WIDTH + sx[q]) * 4;
			printf(" %u,%u,%u,%u", p[0], p[1], p[2], p[3]);
		}
		printf("\n");
	}
	glBindFramebuffer(GL_FRAMEBUFFER, 0);

	/* ---- (b) identical geometry into the window via eglSwapBuffers ---- */
	glDrawBuffer(GL_BACK);
	glReadBuffer(GL_BACK);
	glDisable(GL_DEPTH_TEST);
	draw_quads();
	if (getenv("EGL_HAIKU_SKIP_FINISH") == NULL) glFinish();
	check_gl("window draw");
	if (getenv("EGL_HAIKU_SKIP_READ") == NULL) {
	memset(buf, 0xA5, WIDTH * HEIGHT * 4);
	glReadPixels(0, 0, WIDTH, HEIGHT, GL_RGBA, GL_UNSIGNED_BYTE, buf);
	check_gl("window read");
	check_pixels(buf, WIDTH * 4, false, false);
	{
		int sx[4] = { WIDTH / 4, 3 * WIDTH / 4, WIDTH / 4, 3 * WIDTH / 4 };
		int sy[4] = { HEIGHT / 4, HEIGHT / 4, 3 * HEIGHT / 4, 3 * HEIGHT / 4 };
		printf("WINDOW glReadPixels(GL_BACK) samples:");
		for (int q = 0; q < 4; ++q) {
			unsigned char *p = buf + (sy[q] * WIDTH + sx[q]) * 4;
			printf(" %u,%u,%u,%u", p[0], p[1], p[2], p[3]);
		}
		printf("\n");
		dump_ppm("/tmp/winfbo-winread.ppm", buf, WIDTH * 4, WIDTH, HEIGHT, true);
	}
	}
	if (!eglSwapBuffers(dpy, s))
		{ printf("FAIL eglSwapBuffers error %#x\n", eglGetError()); ++failures; }
	else
		printf("eglSwapBuffers ok\n");

	check_gl("swap");
	eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	eglDestroyContext(dpy, c);
	eglDestroySurface(dpy, s);
	eglTerminate(dpy);
	free(buf);
	printf("%s failures=%u\n", failures ? "FAIL" : "PASS", failures);
	return failures ? 1 : 0;
}
