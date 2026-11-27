/* libdrm_haiku shim: <sys/sysmacros.h> for Haiku (major/minor/makedev).
 *
 * Haiku has no <sys/sysmacros.h> and no major()/minor() macros. Some Intel/Mesa
 * files pull these in via MAJOR_IN_SYSMACROS (autoconf-style). Haiku's st_rdev is
 * documented "not used", so the exact encoding only matters for display; use the
 * conventional Linux 8:8 split.
 */
#ifndef _SYS_SYSMACROS_H_
#define _SYS_SYSMACROS_H_

#ifndef major
#define major(dev) ((unsigned int)(((dev) >> 8) & 0xff))
#endif
#ifndef minor
#define minor(dev) ((unsigned int)((dev) & 0xff))
#endif
#ifndef makedev
#define makedev(maj, min) ((((maj) & 0xff) << 8) | ((min) & 0xff))
#endif

#endif /* _SYS_SYSMACROS_H_ */
