#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#include <dlfcn.h>
#include <math.h>

/*
 JoyConFix.m ultra-safe diagnostic build

 This version does not remap anything and does not install button handlers.
 It only labels GameController button objects and logs when MeloNX reads a
 pressed value. Search device logs for:

   [JoyConDiag]

 Press A, B, X, Y, SL and SR one by one in separated Joy-Con mode, then send
 the matching log lines.
*/

static char kJCFLabelKey;
static char kJCFLastValueKey;
static char kJCFLastPressedKey;

static IMP gOrigExtButtonA;
static IMP gOrigExtButtonB;
static IMP gOrigExtButtonX;
static IMP gOrigExtButtonY;
static IMP gOrigExtLeftShoulder;
static IMP gOrigExtRightShoulder;
static IMP gOrigExtLeftTrigger;
static IMP gOrigExtRightTrigger;

static IMP gOrigMicroButtonA;
static IMP gOrigMicroButtonX;

static IMP gOrigButtonValue;
static IMP gOrigButtonPressed;

static NSString *JCFString(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return value;
    }
    return value ? [value description] : @"";
}

static id JCFCallId(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || !selector || ![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString *JCFButtonName(id button) {
    if (!button) {
        return @"<nil>";
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"ptr=%p", button]];
    [parts addObject:[NSString stringWithFormat:@"class=%@", NSStringFromClass([button class])]];

    for (NSString *selectorName in @[@"localizedName", @"unmappedLocalizedName", @"sfSymbolsName", @"name"]) {
        id value = JCFCallId(button, selectorName);
        if (value) {
            [parts addObject:[NSString stringWithFormat:@"%@=%@", selectorName, JCFString(value)]];
        }
    }

    return [parts componentsJoinedByString:@" "];
}

static void JCFLabel(id button, NSString *label) {
    if (!button || label.length == 0) {
        return;
    }

    NSString *oldLabel = objc_getAssociatedObject(button, &kJCFLabelKey);
    if (oldLabel.length == 0) {
        objc_setAssociatedObject(button, &kJCFLabelKey, label, OBJC_ASSOCIATION_COPY_NONATOMIC);
        NSLog(@"[JoyConDiag] LABEL %@ %@", label, JCFButtonName(button));
    }
}

static NSString *JCFLabelFor(id button) {
    NSString *label = objc_getAssociatedObject(button, &kJCFLabelKey);
    if (label.length > 0) {
        return label;
    }
    return [NSString stringWithFormat:@"unlabeled.%@", NSStringFromClass([button class])];
}

static id JCFProfileButton(id self, SEL _cmd, IMP original, NSString *label) {
    id button = ((id (*)(id, SEL))original)(self, _cmd);
    JCFLabel(button, label);
    return button;
}

static id JCFExtButtonA(id self, SEL _cmd) {
    return JCFProfileButton(self, _cmd, gOrigExtButtonA, @"extended.buttonA");
}

static id JCFExtButtonB(id self, SEL _cmd) {
    return JCFProfileButton(self, _cmd, gOrigExtButtonB, @"extended.buttonB");
}

static id JCFExtButtonX(id self, SEL _cmd) {
    return JCFProfileButton(self, _cmd, gOrigExtButtonX, @"extended.buttonX");
}

static id JCFExtButtonY(id self, SEL _cmd) {
    return JCFProfileButton(self, _cmd, gOrigExtButtonY, @"extended.buttonY");
}

static id JCFExtLeftShoulder(id self, SEL _cmd) {
    return JCFProfileButton(self, _cmd, gOrigExtLeftShoulder, @"extended.leftShoulder");
}

static id JCFExtRightShoulder(id self, SEL _cmd) {
    return JCFProfileButton(self, _cmd, gOrigExtRightShoulder, @"extended.rightShoulder");
}

static id JCFExtLeftTrigger(id self, SEL _cmd) {
    return JCFProfileButton(self, _cmd, gOrigExtLeftTrigger, @"extended.leftTrigger");
}

static id JCFExtRightTrigger(id self, SEL _cmd) {
    return JCFProfileButton(self, _cmd, gOrigExtRightTrigger, @"extended.rightTrigger");
}

static id JCFMicroButtonA(id self, SEL _cmd) {
    return JCFProfileButton(self, _cmd, gOrigMicroButtonA, @"micro.buttonA");
}

static id JCFMicroButtonX(id self, SEL _cmd) {
    return JCFProfileButton(self, _cmd, gOrigMicroButtonX, @"micro.buttonX");
}

static void JCFLogButtonIfChanged(id button, float value, BOOL pressed) {
    NSNumber *lastValueNumber = objc_getAssociatedObject(button, &kJCFLastValueKey);
    NSNumber *lastPressedNumber = objc_getAssociatedObject(button, &kJCFLastPressedKey);

    float lastValue = lastValueNumber ? lastValueNumber.floatValue : -999.0f;
    BOOL lastPressed = lastPressedNumber ? lastPressedNumber.boolValue : NO;
    BOOL changed = !lastValueNumber || fabsf(lastValue - value) > 0.01f || lastPressed != pressed;

    if (!changed) {
        return;
    }

    objc_setAssociatedObject(button, &kJCFLastValueKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kJCFLastPressedKey, @(pressed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (pressed || value > 0.10f || lastPressed || lastValue > 0.10f) {
        NSLog(@"[JoyConDiag] READ %@ value=%.3f pressed=%@ %@",
              JCFLabelFor(button),
              value,
              pressed ? @"YES" : @"NO",
              JCFButtonName(button));
    }
}

static float JCFButtonValue(id self, SEL _cmd) {
    float value = ((float (*)(id, SEL))gOrigButtonValue)(self, _cmd);
    BOOL pressed = NO;

    if (gOrigButtonPressed) {
        pressed = ((BOOL (*)(id, SEL))gOrigButtonPressed)(self, @selector(isPressed));
    } else if ([self respondsToSelector:@selector(isPressed)]) {
        pressed = ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(isPressed));
    } else {
        pressed = value > 0.5f;
    }

    JCFLogButtonIfChanged(self, value, pressed);
    return value;
}

static BOOL JCFButtonPressed(id self, SEL _cmd) {
    BOOL pressed = ((BOOL (*)(id, SEL))gOrigButtonPressed)(self, _cmd);
    float value = 0.0f;

    if (gOrigButtonValue) {
        value = ((float (*)(id, SEL))gOrigButtonValue)(self, @selector(value));
    }

    JCFLogButtonIfChanged(self, value, pressed);
    return pressed;
}

static void JCFSwizzle(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        return;
    }

    if (originalOut) {
        *originalOut = method_getImplementation(method);
    }
    method_setImplementation(method, replacement);
}

static void JCFDumpController(GCController *controller) {
    if (!controller) {
        return;
    }

    NSLog(@"[JoyConDiag] CONTROLLER ptr=%p vendorName=%@ productCategory=%@ attached=%@",
          controller,
          controller.vendorName,
          controller.productCategory,
          controller.attachedToDevice ? @"YES" : @"NO");

    GCExtendedGamepad *extended = controller.extendedGamepad;
    if (extended) {
        (void)extended.buttonA;
        (void)extended.buttonB;
        (void)extended.buttonX;
        (void)extended.buttonY;
        (void)extended.leftShoulder;
        (void)extended.rightShoulder;
        (void)extended.leftTrigger;
        (void)extended.rightTrigger;
    }

    GCMicroGamepad *micro = controller.microGamepad;
    if (micro) {
        (void)micro.buttonA;
        (void)micro.buttonX;
    }

    id profile = JCFCallId(controller, @"physicalInputProfile");
    id buttons = JCFCallId(profile, @"buttons");
    if ([buttons isKindOfClass:NSDictionary.class]) {
        NSLog(@"[JoyConDiag] PHYSICAL buttons.count=%lu keys=%@",
              (unsigned long)((NSDictionary *)buttons).count,
              [[(NSDictionary *)buttons allKeys] componentsJoinedByString:@", "]);
    }
}

static void JCFDumpAllControllers(void) {
    NSArray<GCController *> *controllers = [GCController controllers];
    NSLog(@"[JoyConDiag] CONTROLLERS count=%lu", (unsigned long)controllers.count);
    for (GCController *controller in controllers) {
        JCFDumpController(controller);
    }
}

__attribute__((constructor))
static void JCFInstall(void) {
    @autoreleasepool {
        dlopen("/System/Library/Frameworks/GameController.framework/GameController", RTLD_LAZY | RTLD_GLOBAL);

        JCFSwizzle(GCExtendedGamepad.class, @selector(buttonA), (IMP)JCFExtButtonA, &gOrigExtButtonA);
        JCFSwizzle(GCExtendedGamepad.class, @selector(buttonB), (IMP)JCFExtButtonB, &gOrigExtButtonB);
        JCFSwizzle(GCExtendedGamepad.class, @selector(buttonX), (IMP)JCFExtButtonX, &gOrigExtButtonX);
        JCFSwizzle(GCExtendedGamepad.class, @selector(buttonY), (IMP)JCFExtButtonY, &gOrigExtButtonY);
        JCFSwizzle(GCExtendedGamepad.class, @selector(leftShoulder), (IMP)JCFExtLeftShoulder, &gOrigExtLeftShoulder);
        JCFSwizzle(GCExtendedGamepad.class, @selector(rightShoulder), (IMP)JCFExtRightShoulder, &gOrigExtRightShoulder);
        JCFSwizzle(GCExtendedGamepad.class, @selector(leftTrigger), (IMP)JCFExtLeftTrigger, &gOrigExtLeftTrigger);
        JCFSwizzle(GCExtendedGamepad.class, @selector(rightTrigger), (IMP)JCFExtRightTrigger, &gOrigExtRightTrigger);

        JCFSwizzle(GCMicroGamepad.class, @selector(buttonA), (IMP)JCFMicroButtonA, &gOrigMicroButtonA);
        JCFSwizzle(GCMicroGamepad.class, @selector(buttonX), (IMP)JCFMicroButtonX, &gOrigMicroButtonX);

        JCFSwizzle(GCControllerButtonInput.class, @selector(value), (IMP)JCFButtonValue, &gOrigButtonValue);
        JCFSwizzle(GCControllerButtonInput.class, @selector(isPressed), (IMP)JCFButtonPressed, &gOrigButtonPressed);

        NSLog(@"[JoyConDiag] passive diagnostic tweak loaded");

        [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *notification) {
            NSLog(@"[JoyConDiag] CONNECT notification");
            JCFDumpController(notification.object);
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            JCFDumpAllControllers();
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            JCFDumpAllControllers();
        });
    }
}
