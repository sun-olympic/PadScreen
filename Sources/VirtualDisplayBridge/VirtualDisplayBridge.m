#import "VirtualDisplayBridge.h"

#import <Foundation/Foundation.h>
#import <objc/message.h>

static Class PadScreenClass(NSString *name) {
    return NSClassFromString(name);
}

bool PadScreenVirtualDisplayClassesAvailable(void) {
    return PadScreenClass(@"CGVirtualDisplay")
        && PadScreenClass(@"CGVirtualDisplayDescriptor")
        && PadScreenClass(@"CGVirtualDisplaySettings")
        && PadScreenClass(@"CGVirtualDisplayMode");
}

PadScreenVirtualDisplayRef PadScreenVirtualDisplayCreate(
    uint32_t width,
    uint32_t height,
    double refreshRate,
    CGDirectDisplayID *displayID
) {
    if (!displayID || !PadScreenVirtualDisplayClassesAvailable()) return NULL;

    Class descriptorClass = PadScreenClass(@"CGVirtualDisplayDescriptor");
    Class displayClass = PadScreenClass(@"CGVirtualDisplay");
    Class settingsClass = PadScreenClass(@"CGVirtualDisplaySettings");
    Class modeClass = PadScreenClass(@"CGVirtualDisplayMode");

    id descriptor = [[descriptorClass alloc] init];
    [descriptor setValue:@"PadScreen" forKey:@"name"];
    [descriptor setValue:@(width) forKey:@"maxPixelsWide"];
    [descriptor setValue:@(height) forKey:@"maxPixelsHigh"];
    [descriptor setValue:[NSValue valueWithSize:NSMakeSize(286, 179)] forKey:@"sizeInMillimeters"];
    [descriptor setValue:@(0x5053) forKey:@"vendorID"];
    [descriptor setValue:@(0x0001) forKey:@"productID"];
    [descriptor setValue:@(0x0001) forKey:@"serialNum"];
    ((void (*)(id, SEL, dispatch_queue_t))objc_msgSend)(
        descriptor,
        NSSelectorFromString(@"setDispatchQueue:"),
        dispatch_get_main_queue()
    );
    void (^terminationHandler)(id, id) = ^(id reason, id display) {
        (void)reason;
        (void)display;
    };
    [descriptor setValue:[terminationHandler copy] forKey:@"terminationHandler"];

    id display = ((id (*)(id, SEL, id))objc_msgSend)(
        [displayClass alloc],
        NSSelectorFromString(@"initWithDescriptor:"),
        descriptor
    );
    if (!display) return NULL;

    id mode = ((id (*)(id, SEL, NSUInteger, NSUInteger, CGFloat))objc_msgSend)(
        [modeClass alloc],
        NSSelectorFromString(@"initWithWidth:height:refreshRate:"),
        (NSUInteger)width,
        (NSUInteger)height,
        (CGFloat)refreshRate
    );
    id settings = [[settingsClass alloc] init];
    [settings setValue:@(1) forKey:@"hiDPI"];
    [settings setValue:@[mode] forKey:@"modes"];
    BOOL applied = ((BOOL (*)(id, SEL, id))objc_msgSend)(
        display,
        NSSelectorFromString(@"applySettings:"),
        settings
    );
    if (!applied) return NULL;

    *displayID = ((CGDirectDisplayID (*)(id, SEL))objc_msgSend)(
        display,
        NSSelectorFromString(@"displayID")
    );
    return (__bridge_retained void *)display;
}

void PadScreenVirtualDisplayDestroy(PadScreenVirtualDisplayRef display) {
    if (display) CFRelease(display);
}
