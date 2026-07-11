#ifndef PADSCREEN_VIRTUAL_DISPLAY_BRIDGE_H
#define PADSCREEN_VIRTUAL_DISPLAY_BRIDGE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *PadScreenVirtualDisplayRef;

bool PadScreenVirtualDisplayClassesAvailable(void);
PadScreenVirtualDisplayRef PadScreenVirtualDisplayCreate(
    uint32_t width,
    uint32_t height,
    double refreshRate,
    CGDirectDisplayID *displayID
);
void PadScreenVirtualDisplayDestroy(PadScreenVirtualDisplayRef display);

#ifdef __cplusplus
}
#endif

#endif
