/*
 * libdrm_haiku — minimal <xf86drm.h> shim for Mesa on Haiku.
 *
 * Mesa includes <xf86drm.h> unconditionally in a number of TUs (u_sync_provider.c,
 * intel_device_info uses util/libdrm.h instead, iris_bufmgr.c, iris_batch.c, ...).
 * On Haiku meson sets dep_libdrm = null (system_has_kms_drm excludes haiku), so the
 * C code still needs the header and the symbols, but there is no libdrm package.
 *
 * This header is header-only: every needed entry point is a static inline no-op that
 * returns -ENOSYS (or, for drmIoctl, forwards to ioctl). Nothing on the iris/i915
 * critical path calls these: iris does real work through intel_ioctl() (inlined in
 * intel/common/intel_gem.h); the prime/dma-buf and syncobj-fd helpers are only used
 * by the unused XE KMD backend and the util sync provider wrappers.
 *
 * Pair with the vendored Mesa headers include/drm-uapi/{drm.h,drm_mode.h}, copied next
 * to this file, so <drm.h> resolves.
 */
#ifndef _XF86DRM_H_
#define _XF86DRM_H_

#include <stdarg.h>
#include <sys/types.h>
#include <unistd.h>     /* Haiku declares ioctl() here */
#include <stdint.h>
#include <errno.h>
#include <drm.h>

#if defined(__cplusplus)
extern "C" {
#endif

#ifndef DRM_MAX_MINOR
#define DRM_MAX_MINOR 64
#endif

#if defined(__linux__)
#define DRM_IOCTL_NR(n) _IOC_NR(n)
#define DRM_IOC_VOID _IOC_NONE
#define DRM_IOC_READ _IOC_READ
#define DRM_IOC_WRITE _IOC_WRITE
#define DRM_IOC_READWRITE _IOC_READ | _IOC_WRITE
#define DRM_IOC(dir, group, nr, size) _IOC(dir, group, nr, size)
#else
#define DRM_IOCTL_NR(n) ((n) & 0xff)
#define DRM_IOC_VOID IOC_VOID
#define DRM_IOC_READ IOC_OUT
#define DRM_IOC_WRITE IOC_IN
#define DRM_IOC_READWRITE IOC_INOUT
#define DRM_IOC(dir, group, nr, size) _IOC(dir, group, nr, size)
#endif

typedef unsigned int drm_magic_t;

#define DRM_DEVICE_GET_PCI_REVISION (1 << 0)

typedef struct _drmPciDeviceInfo {
    uint16_t vendor_id;
    uint16_t device_id;
    uint16_t subvendor_id;
    uint16_t subdevice_id;
    uint8_t revision_id;
} drmPciDeviceInfo, *drmPciDeviceInfoPtr;

typedef struct _drmPciBusInfo {
    uint16_t domain;
    uint8_t bus;
    uint8_t dev;
    uint8_t func;
} drmPciBusInfo, *drmPciBusInfoPtr;

typedef struct _drmDevice {
    char **nodes;
    int available_nodes;
    int bustype;
    union {
        drmPciBusInfoPtr pci;
    } businfo;
    union {
        drmPciDeviceInfoPtr pci;
    } deviceinfo;
} drmDevice, *drmDevicePtr;

typedef struct _drmVersion {
    int version_major;
    int version_minor;
    int version_patchlevel;
    int name_len;
    char *name;
    int date_len;
    char *date;
    int desc_len;
    char *desc;
} drmVersion, *drmVersionPtr;

static inline int drmIoctl(int fd, unsigned long request, void *arg)
{
    return ioctl(fd, request, arg);
}

static inline drmVersionPtr drmGetVersion(int fd) { (void)fd; return NULL; }
static inline void drmFreeVersion(drmVersionPtr v) { (void)v; }
static inline int drmGetCap(int fd, uint64_t capability, uint64_t *value)
{
    (void)fd; (void)capability; (void)value; return -ENOSYS;
}
static inline int drmGetMagic(int fd, drm_magic_t *magic)
{
    (void)fd; (void)magic; return -ENOSYS;
}
static inline char *drmGetDeviceNameFromFd2(int fd) { (void)fd; return NULL; }

static inline int drmGetDevice2(int fd, uint32_t flags, drmDevicePtr *device)
{
    (void)fd; (void)flags; (void)device; return -ENOENT;
}
static inline int drmGetDevices2(uint32_t flags, drmDevicePtr devices[], int max_devices)
{
    (void)flags; (void)devices; (void)max_devices; return -ENOENT;
}
static inline int drmGetDeviceFromDevId(dev_t dev_id, uint32_t flags, drmDevicePtr *device)
{
    (void)dev_id; (void)flags; (void)device; return -ENOENT;
}
static inline void drmFreeDevice(drmDevicePtr *device) { (void)device; }
static inline void drmFreeDevices(drmDevicePtr devices[], int count)
{
    (void)devices; (void)count;
}

static inline int drmPrimeHandleToFD(int fd, uint32_t handle, uint32_t flags, int *prime_fd)
{
    (void)fd; (void)handle; (void)flags; (void)prime_fd; return -ENOSYS;
}
static inline int drmPrimeFDToHandle(int fd, int prime_fd, uint32_t *handle)
{
    (void)fd; (void)prime_fd; (void)handle; return -ENOSYS;
}

static inline int drmSyncobjCreate(int fd, uint32_t flags, uint32_t *handle)
{
    (void)fd; (void)flags; (void)handle; return -ENOSYS;
}
static inline int drmSyncobjDestroy(int fd, uint32_t handle)
{
    (void)fd; (void)handle; return -ENOSYS;
}
static inline int drmSyncobjHandleToFD(int fd, uint32_t handle, int *obj_fd)
{
    (void)fd; (void)handle; (void)obj_fd; return -ENOSYS;
}
static inline int drmSyncobjFDToHandle(int fd, int obj_fd, uint32_t *handle)
{
    (void)fd; (void)obj_fd; (void)handle; return -ENOSYS;
}
static inline int drmSyncobjImportSyncFile(int fd, uint32_t handle, int sync_file_fd)
{
    (void)fd; (void)handle; (void)sync_file_fd; return -ENOSYS;
}
static inline int drmSyncobjExportSyncFile(int fd, uint32_t handle, int *sync_file_fd)
{
    (void)fd; (void)handle; (void)sync_file_fd; return -ENOSYS;
}
static inline int drmSyncobjWait(int fd, uint32_t *handles, unsigned num_handles,
                                 int64_t timeout_nsec, unsigned flags,
                                 uint32_t *first_signaled)
{
    (void)fd; (void)handles; (void)num_handles; (void)timeout_nsec;
    (void)flags; (void)first_signaled; return -ENOSYS;
}
static inline int drmSyncobjReset(int fd, const uint32_t *handles, uint32_t handle_count)
{
    (void)fd; (void)handles; (void)handle_count; return -ENOSYS;
}
static inline int drmSyncobjSignal(int fd, const uint32_t *handles, uint32_t handle_count)
{
    (void)fd; (void)handles; (void)handle_count; return -ENOSYS;
}
static inline int drmSyncobjTimelineSignal(int fd, const uint32_t *handles,
                                           uint64_t *points, uint32_t handle_count)
{
    (void)fd; (void)handles; (void)points; (void)handle_count; return -ENOSYS;
}
static inline int drmSyncobjTimelineWait(int fd, uint32_t *handles, uint64_t *points,
                                         unsigned num_handles, int64_t timeout_nsec,
                                         unsigned flags, uint32_t *first_signaled)
{
    (void)fd; (void)handles; (void)points; (void)num_handles; (void)timeout_nsec;
    (void)flags; (void)first_signaled; return -ENOSYS;
}
static inline int drmSyncobjQuery(int fd, uint32_t *handles, uint64_t *points,
                                  uint32_t handle_count)
{
    (void)fd; (void)handles; (void)points; (void)handle_count; return -ENOSYS;
}
static inline int drmSyncobjQuery2(int fd, uint32_t *handles, uint64_t *points,
                                   uint32_t handle_count, uint32_t flags)
{
    (void)fd; (void)handles; (void)points; (void)handle_count; (void)flags;
    return -ENOSYS;
}
static inline int drmSyncobjTransfer(int fd, uint32_t dst_handle, uint64_t dst_point,
                                     uint32_t src_handle, uint64_t src_point, uint32_t flags)
{
    (void)fd; (void)dst_handle; (void)dst_point; (void)src_handle;
    (void)src_point; (void)flags; return -ENOSYS;
}
static inline int drmSyncobjEventfd(int fd, uint32_t handle, uint64_t point,
                                    int ev_fd, uint32_t flags)
{
    (void)fd; (void)handle; (void)point; (void)ev_fd; (void)flags; return -ENOSYS;
}

#if defined(__cplusplus)
}
#endif

#endif /* _XF86DRM_H_ */
