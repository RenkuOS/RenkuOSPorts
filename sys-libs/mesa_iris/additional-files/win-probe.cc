/*
 * win-probe - drive the Haiku EGL window-surface present path with our own
 * BitmapHook, draw a known pattern, and dump both what the present hands back
 * (the BitmapHook bitmap) and a reference GL read-back, for comparison.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>

#include <Application.h>
#include <Bitmap.h>
#include <Rect.h>

#define WIDTH 128
#define HEIGHT 128

/* Must match Mesa's hgl_sw_winsys.h (private header). */
class BitmapHook {
public:
	virtual ~BitmapHook() {};
	virtual void GetSize(uint32_t &width, uint32_t &height) = 0;
	virtual BBitmap *SetBitmap(BBitmap *bmp) = 0;
};

static int failures;

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
	MyHook() : fCurrent(NULL), fFrames(0), fWidth(WIDTH), fHeight(HEIGHT) {}
	void Resize(uint32_t w, uint32_t h) { fWidth = w; fHeight = h; }
	virtual void GetSize(uint32_t &width, uint32_t &height)
	{
		width = fWidth;
		height = fHeight;
	}
	virtual BBitmap *SetBitmap(BBitmap *bmp)
	{
		BBitmap *old = fCurrent;
		fCurrent = bmp;
		if (bmp != NULL) {
			++fFrames;
			int w = fWidth, h = fHeight;
			// Software winsys may allocate a padded bitmap; validate only
			// the drawable region, using BytesPerRow for its stride.
			if (bmp->Bounds().IntegerWidth()+1 < w || bmp->Bounds().IntegerHeight()+1 < h) {
				++failures; return old;
			}
			const unsigned char *bits = (const unsigned char *)bmp->Bits();
			// Gallium's window render target has its origin at the top left.
			const unsigned char expected[4][3] = {
				{255, 0, 0}, {255, 255, 255}, {0, 0, 255}, {0, 255, 0}
			}; // BGR: blue/white above red/green
			for (int q = 0; q < 4; ++q) {
				int x = (q % 2 ? 3 : 1) * w / 4;
				int y = (q / 2 ? 3 : 1) * h / 4;
				const unsigned char *pixel = bits + y * bmp->BytesPerRow() + x * 4;
				if (memcmp(pixel, expected[q], 3) != 0) {
					if (failures < 8)
						printf("FAIL bitmap frame %u quadrant %d BGR=%u,%u,%u\n",
							fFrames, q, pixel[0], pixel[1], pixel[2]);
					++failures;
				}
			}
			// Check the complete image, excluding a two-pixel band around
			// geometric edges where rasterization rules affect coverage.
			for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
				bool edge = false;
				const float bounds[] = {.05f, .45f, .55f, .95f};
				for (unsigned e = 0; e < 4; ++e)
					if (abs(x - (int)(bounds[e] * w)) <= 2 ||
					    abs(y - (int)(bounds[e] * h)) <= 2) edge = true;
				if (edge) continue;
				float u = (x + .5f) / w, v = (y + .5f) / h;
				bool colored = ((u > .05f && u < .45f) || (u > .55f && u < .95f)) &&
					((v > .05f && v < .45f) || (v > .55f && v < .95f));
				const unsigned char black[3] = {};
				const unsigned char *want = colored ? expected[(v > .5f ? 2 : 0) + (u > .5f)] : black;
				const unsigned char *pixel = bits + y * bmp->BytesPerRow() + x * 4;
				if (memcmp(pixel, want, 3) != 0) {
					if (failures < 8) printf("FAIL full image frame %u at %d,%d BGR=%u,%u,%u expected=%u,%u,%u\n", fFrames, x, y, pixel[0],pixel[1],pixel[2],want[0],want[1],want[2]);
					++failures;
				}
			}
			if (fFrames == 1)
				dump_ppm("/tmp/win-bitmap.ppm", bits,
					bmp->BytesPerRow(), w, h, false);
		}
		return old;
	}

private:
	BBitmap *fCurrent;
	unsigned fFrames;
	uint32_t fWidth, fHeight;
};

int
main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	BApplication application("application/x-vnd.haiku-present-test");
	MyHook hook;

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

	GLint samples = -1, sample_buffers = -1;
	glGetIntegerv(GL_SAMPLES, &samples);
	glGetIntegerv(GL_SAMPLE_BUFFERS, &sample_buffers);
	printf("samples=%d sample_buffers=%d\n", samples, sample_buffers);
	glDrawBuffer(GL_BACK);
	glReadBuffer(GL_BACK);
	for (unsigned frame = 0; frame < 300; ++frame) {
	uint32_t width, height;
	hook.GetSize(width, height);
	glViewport(0, 0, width, height);
	glDisable(GL_DEPTH_TEST);
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(0.0, 1.0, 0.0, 1.0, -1.0, 1.0);
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();

	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);

	/* four coloured quadrants */
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
	if (!eglSwapBuffers(dpy, s)) {
		printf("FAIL eglSwapBuffers frame %u error %#x\n", frame, eglGetError());
		++failures;
		break;
	}
	if (glGetError() != GL_NO_ERROR) {
		++failures;
		break;
	}
	if (failures)
		break;
	if (frame == 149 && getenv("EGL_HAIKU_TEST_RESIZE")) {
		hook.Resize(296, 269);
		// Notify/rebind the resized drawable before setting its viewport.
		if (!eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT) ||
		    !eglMakeCurrent(dpy, s, s, c)) { ++failures; break; }
	}
	}
	eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	eglDestroyContext(dpy, c);
	eglDestroySurface(dpy, s);
	eglTerminate(dpy);
	printf("%s: 300 frame present, %d mismatches\n", failures ? "FAIL" : "PASS", failures);

	printf("DONE\n");
	return failures ? 1 : 0;
}
