#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>

/*
 JoyConFix.m diagnostic build

 This build does not change controller input.

 It logs exactly what MeloNX/LiveContainer sees through Apple's GameController
 API. Use it to press A, B, X, Y, SL and SR on each separated fake Joy-Con.

 Search logs for:

   [JoyConDiag]

 The important part is which physical/profile button fires when you press each
 real button. Once we know that, the final remap can be exact instead of guessed.
*/

static char kJCFDiagInstalledKey;

static id JCFCallId(id object, SEL selector) {
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

static NSString *JCFButtonInfo(id button) {
    if (!button) {
        return @"<nil>";
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"ptr=%p", button]];
    [parts addObject:[NSString stringWithFormat:@"class=%@", NSStringFromClass([button class])]];

    for (NSString *selectorName in @[@"localizedName", @"unmappedLocalizedName", @"sfSymbolsName", @"name"]) {
        id value = JCFCallId(button, NSSelectorFromString(selectorName));
        if (value) {
            [parts addObject:[NSString stringWithFormat:@"%@=%@", selectorName, JCFString(value)]];
        }
    }

    id aliases = JCFCallId(button, NSSelectorFromString(@"aliases"));
    if (aliases) {
        [parts addObject:[NSString stringWithFormat:@"aliases=%@", aliases]];
    }

    if ([button respondsToSelector:@selector(value)]) {
        float value = ((float (*)(id, SEL))objc_msgSend)(button, @selector(value));
        [parts addObject:[NSString stringWithFormat:@"value=%.3f", value]];
    }

    if ([button respondsToSelector:@selector(isPressed)]) {
        BOOL pressed = ((BOOL (*)(id, SEL))objc_msgSend)(button, @selector(isPressed));
        [parts addObject:[NSString stringWithFormat:@"pressed=%@", pressed ? @"YES" : @"NO"]];
    }

    return [parts componentsJoinedByString:@" "];
}

static void JCFInstallButtonLogger(id button, NSString *label) {
    if (!button || objc_getAssociatedObject(button, &kJCFDiagInstalledKey)) {
        return;
    }

    objc_setAssociatedObject(button, &kJCFDiagInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"[JoyConDiag] INSTALL %@ %@", label, JCFButtonInfo(button));

    if ([button respondsToSelector:@selector(setPressedChangedHandler:)]) {
        void (^pressedHandler)(id, float, BOOL) = ^(id element, float value, BOOL pressed) {
            NSLog(@"[JoyConDiag] PRESSED %@ value=%.3f pressed=%@ %@", label, value, pressed ? @"YES" : @"NO", JCFButtonInfo(element));
        };
        ((void (*)(id, SEL, id))objc_msgSend)(button, @selector(setPressedChangedHandler:), pressedHandler);
    }

    if ([button respondsToSelector:@selector(setValueChangedHandler:)]) {
        void (^valueHandler)(id, float, BOOL) = ^(id element, float value, BOOL pressed) {
            NSLog(@"[JoyConDiag] VALUE %@ value=%.3f pressed=%@ %@", label, value, pressed ? @"YES" : @"NO", JCFButtonInfo(element));
        };
        ((void (*)(id, SEL, id))objc_msgSend)(button, @selector(setValueChangedHandler:), valueHandler);
    }
}

static void JCFDumpDictionary(NSString *title, NSDictionary *dictionary) {
    NSLog(@"[JoyConDiag] %@ count=%lu", title, (unsigned long)dictionary.count);
    for (id key in dictionary) {
        id value = dictionary[key];
        NSString *label = [NSString stringWithFormat:@"%@ key=%@", title, key];
        NSLog(@"[JoyConDiag] %@ %@", label, JCFButtonInfo(value));
        JCFInstallButtonLogger(value, label);
    }
}

static void JCFDumpArray(NSString *title, NSArray *array) {
    NSLog(@"[JoyConDiag] %@ count=%lu", title, (unsigned long)array.count);
    NSUInteger index = 0;
    for (id value in array) {
        NSString *label = [NSString stringWithFormat:@"%@[%lu]", title, (unsigned long)index];
        NSLog(@"[JoyConDiag] %@ %@", label, JCFButtonInfo(value));
        JCFInstallButtonLogger(value, label);
        index++;
    }
}

static void JCFInspectController(GCController *controller) {
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
        NSLog(@"[JoyConDiag] EXTENDED ptr=%p", extended);
        JCFInstallButtonLogger(extended.buttonA, @"extended.buttonA");
        JCFInstallButtonLogger(extended.buttonB, @"extended.buttonB");
        JCFInstallButtonLogger(extended.buttonX, @"extended.buttonX");
        JCFInstallButtonLogger(extended.buttonY, @"extended.buttonY");
        JCFInstallButtonLogger(extended.leftShoulder, @"extended.leftShoulder");
        JCFInstallButtonLogger(extended.rightShoulder, @"extended.rightShoulder");
        JCFInstallButtonLogger(extended.leftTrigger, @"extended.leftTrigger");
        JCFInstallButtonLogger(extended.rightTrigger, @"extended.rightTrigger");
    }

    GCMicroGamepad *micro = controller.microGamepad;
    if (micro) {
        NSLog(@"[JoyConDiag] MICRO ptr=%p", micro);
        JCFInstallButtonLogger(micro.buttonA, @"micro.buttonA");
        JCFInstallButtonLogger(micro.buttonX, @"micro.buttonX");
    }

    id profile = JCFCallId(controller, NSSelectorFromString(@"physicalInputProfile"));
    if (profile) {
        NSLog(@"[JoyConDiag] PHYSICAL_PROFILE ptr=%p class=%@", profile, NSStringFromClass([profile class]));

        id buttons = JCFCallId(profile, NSSelectorFromString(@"buttons"));
        if ([buttons isKindOfClass:NSDictionary.class]) {
            JCFDumpDictionary(@"physical.buttons", buttons);
        }

        id elements = JCFCallId(profile, NSSelectorFromString(@"elements"));
        if ([elements isKindOfClass:NSDictionary.class]) {
            JCFDumpDictionary(@"physical.elements", elements);
        }

        id allButtons = JCFCallId(profile, NSSelectorFromString(@"allButtons"));
        if ([allButtons isKindOfClass:NSArray.class]) {
            JCFDumpArray(@"physical.allButtons", allButtons);
        }
    }
}

static void JCFInspectAllControllers(void) {
    NSArray<GCController *> *controllers = [GCController controllers];
    NSLog(@"[JoyConDiag] CONTROLLERS count=%lu", (unsigned long)controllers.count);
    for (GCController *controller in controllers) {
        JCFInspectController(controller);
    }
}

__attribute__((constructor))
static void JCFInstall(void) {
    @autoreleasepool {
        dlopen("/System/Library/Frameworks/GameController.framework/GameController", RTLD_LAZY | RTLD_GLOBAL);

        NSLog(@"[JoyConDiag] diagnostic tweak loaded");

        [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *notification) {
            NSLog(@"[JoyConDiag] CONNECT notification");
            JCFInspectController(notification.object);
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            JCFInspectAllControllers();
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            JCFInspectAllControllers();
        });
    }
}
