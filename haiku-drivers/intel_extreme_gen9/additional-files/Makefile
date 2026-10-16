# Standalone build of the pinned RenkuOS/Haiku driver sources.
# Matches Haiku KernelAddon flags; uses the build system's haiku_devel ABI.
DRIVER_DIR = src/add-ons/kernel/drivers/graphics/intel_extreme
PRIVATE_HEADERS ?= /boot/system/develop/headers/private
DEVEL_LIB ?= /boot/system/develop/lib
INCLUDES = -I. -I$(PRIVATE_HEADERS) -Iheaders/private/graphics/intel_extreme \
 -Iheaders/private/graphics/common -Iheaders/private/graphics/vesa \
 -Iheaders/private/graphics -I$(PRIVATE_HEADERS)/kernel -I$(PRIVATE_HEADERS)/kernel/arch/x86 -I$(PRIVATE_HEADERS)/kernel/boot/platform/bios_ia32 \
 -I$(PRIVATE_HEADERS)/libroot -I$(PRIVATE_HEADERS)/shared \
 -I$(PRIVATE_HEADERS)/system -I$(PRIVATE_HEADERS)/system/arch/x86_64 -I$(PRIVATE_HEADERS)/graphics
KFLAGS = -O2 -g -D_KERNEL_MODE=1 -DDEBUG=0 -ffreestanding \
 -fno-semantic-interposition -fno-tree-vectorize -mno-red-zone \
 -fno-omit-frame-pointer -fno-stack-protector -fPIC -Wall -Wno-multichar
CPPFLAGS += $(INCLUDES)
CFLAGS += $(KFLAGS)
CXXFLAGS += $(KFLAGS) -fno-exceptions -fno-rtti -fno-use-cxa-atexit -std=gnu++17
SOURCES = bios driver device intel_extreme power render_node
OBJECTS = $(addprefix objects/,$(addsuffix .o,$(SOURCES))) objects/kernel_cpp.o objects/memory_manager.o

all: objects/intel_extreme objects/intel-gen9-stress
objects:
	mkdir -p $@
objects/%.o: $(DRIVER_DIR)/%.cpp | objects
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@
objects/kernel_cpp.o: src/system/kernel/util/kernel_cpp.cpp | objects
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@
objects/memory_manager.o: src/add-ons/kernel/drivers/graphics/common/memory_manager.c | objects
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
objects/intel_extreme: $(OBJECTS)
	$(CXX) -shared -nostdlib -Wl,--no-undefined,-soname,intel_extreme,-z,max-page-size=0x1000 -o $@ $(OBJECTS) $(DEVEL_LIB)/haiku_version_glue.o $(DEVEL_LIB)/_KERNEL_ -lgcc
objects/intel-gen9-stress: $(DRIVER_DIR)/tests/drmstress.cpp | objects
	$(CXX) -O2 -Iheaders/private/graphics $< -o $@
