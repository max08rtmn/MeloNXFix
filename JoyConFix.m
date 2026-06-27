#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#include <dlfcn.h>

/*
 JoyConFix.m event diagnostic build

 This does not remap buttons, rotate sticks, or hook value/isPressed polling.
 It only labels visible GameController button objects and wraps MeloNX's own
 button event handlers so the original handler still runs.

 Search logs for:

   [JoyConDiag]
*/

static char kJCFLabelKey;
static char kJCFWrappedValueKey;
static char kJCFWrappedPressedKey;

static IMP gOrigSetValueChangedHandler;
static IMP gOrigSetPressedChangedHandler;

static id JCFCallId(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || !selector || ![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString *JCFString(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return value;
    }
    return value ? [value description] : @"";
}

static NSString *JCFDescribeButton(id button) {
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
        NSLog(@"[JoyConDiag] LABEL %@ %@", label, JCFDescribeButton(button));
    }
}

static NSString *JCFLabelFor(id button) {
    NSString *label = objc_getAssociatedObject(button, &kJCFLabelKey);
    if (label.length > 0) {
        return label;
    }
    return [NSString stringWithFormat:@"unlabeled.%@", NSStringFromClass([button class])];
}

static void JCFSetValueChangedHandler(id self, SEL _cmd, id handler) {
    if (!gOrigSetValueChangedHandler) {
        return;
    }

    if (!handler) {
        objc_setAssociatedObject(self, &kJCFWrappedValueKey, nil, OBJC_ASSOCIATION_ASSIGN);
        ((void (*)(id, SEL, id))gOrigSetValueChangedHandler)(self, _cmd, nil);
        return;
    }

    id copiedHandler = [handler copy];
    void (^wrapper)(id, float, BOOL) = ^(id element, float value, BOOL pressed) {
        NSLog(@"[JoyConDiag] EVENT valueChanged %@ value=%.3f pressed=%@ %@",
              JCFLabelFor(element ?: self),
              value,
              pressed ? @"YES" : @"NO",
              JCFDescribeButton(element ?: self));
        ((void (^)(id, float, BOOL))copiedHandler)(element, value, pressed);
    };

    objc_setAssociatedObject(self, &kJCFWrappedValueKey, wrapper, OBJC_ASSOCIATION_COPY_NONATOMIC);
    ((void (*)(id, SEL, id))gOrigSetValueChangedHandler)(self, _cmd, wrapper);
}

static void JCFSetPressedChangedHandler(id self, SEL _cmd, id handler) {
    if (!gOrigSetPressedChangedHandler) {
        return;
    }

    if (!handler) {
        objc_setAssociatedObject(self, &kJCFWrappedPressedKey, nil, OBJC_ASSOCIATION_ASSIGN);
        ((void (*)(id, SEL, id))gOrigSetPressedChangedHandler)(self, _cmd, nil);
        return;
    }

    id copiedHandler = [handler copy];
    void (^wrapper)(id, float, BOOL) = ^(id element, float value, BOOL pressed) {
        NSLog(@"[JoyConDiag] EVENT pressedChanged %@ value=%.3f pressed=%@ %@",
              JCFLabelFor(element ?: self),
              value,
              pressed ? @"YES" : @"NO",
              JCFDescribeButton(element ?: self));
        ((void (^)(id, float, BOOL))copiedHandler)(element, value, pressed);
    };

    objc_setAssociatedObject(self, &kJCFWrappedPressedKey, wrapper, OBJC_ASSOCIATION_COPY_NONATOMIC);
    ((void (*)(id, SEL, id))gOrigSetPressedChangedHandler)(self, _cmd, wrapper);
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

static void JCFLabelPhysicalButtons(GCController *controller) {
    id profile = JCFCallId(controller, @"physicalInputProfile");
    id buttons = JCFCallId(profile, @"buttons");
    if (![buttons isKindOfClass:NSDictionary.class]) {
        return;
    }

    NSDictionary *buttonMap = (NSDictionary *)buttons;
    NSLog(@"[JoyConDiag] PHYSICAL buttons.count=%lu keys=%@",
          (unsigned long)buttonMap.count,
          [[buttonMap allKeys] componentsJoinedByString:@", "]);

    for (id key in buttonMap) {
        JCFLabel(buttonMap[key], [NSString stringWithFormat:@"physical.%@", key]);
    }
}

static void JCFLabelStandardButtons(GCController *controller) {
    GCExtendedGamepad *extended = controller.extendedGamepad;
    if (extended) {
        JCFLabel(extended.buttonA, @"extended.buttonA");
        JCFLabel(extended.buttonB, @"extended.buttonB");
        JCFLabel(extended.buttonX, @"extended.buttonX");
        JCFLabel(extended.buttonY, @"extended.buttonY");
        JCFLabel(extended.leftShoulder, @"extended.leftShoulder");
        JCFLabel(extended.rightShoulder, @"extended.rightShoulder");
        JCFLabel(extended.leftTrigger, @"extended.leftTrigger");
        JCFLabel(extended.rightTrigger, @"extended.rightTrigger");
    }

    GCMicroGamepad *micro = controller.microGamepad;
    if (micro) {
        JCFLabel(micro.buttonA, @"micro.buttonA");
        JCFLabel(micro.buttonX, @"micro.buttonX");
    }
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

    JCFLabelPhysicalButtons(controller);
    JCFLabelStandardButtons(controller);
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

        JCFSwizzle(GCControllerButtonInput.class,
                   NSSelectorFromString(@"setValueChangedHandler:"),
                   (IMP)JCFSetValueChangedHandler,
                   &gOrigSetValueChangedHandler);

        JCFSwizzle(GCControllerButtonInput.class,
                   NSSelectorFromString(@"setPressedChangedHandler:"),
                   (IMP)JCFSetPressedChangedHandler,
                   &gOrigSetPressedChangedHandler);

        NSLog(@"[JoyConDiag] event diagnostic tweak loaded");

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
