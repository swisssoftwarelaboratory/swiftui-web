#include "SwiftUIWebWidgetLauncher.h"
#include <stddef.h>

typedef int (*widgets_main_fn)(int argc, char **argv);

#if defined(__wasm__)
// wasm-ld leaves a weak function nobody defines as null.
extern int swiftui_web_widgets_main(int argc, char **argv) __attribute__((weak));
static widgets_main_fn find_widgets_main(void) { return swiftui_web_widgets_main; }
#else
// Mach-O and ELF refuse an undefined weak function at link time: look it up in the process.
#include <dlfcn.h>
static widgets_main_fn find_widgets_main(void) { return (widgets_main_fn)dlsym(RTLD_DEFAULT, "swiftui_web_widgets_main"); }
#endif

int swiftui_web_launch_widgets(void) {
    widgets_main_fn entry = find_widgets_main();
    if (entry == NULL) return 0;
    entry(0, NULL);
    return 1;
}
