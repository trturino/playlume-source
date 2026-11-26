//
//  SDLMainWrapper.m
//  Moonlight Vision
//
//  Created by Alex Haugland on 1/27/24.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

#define SDL_MAIN_HANDLED
#import "SDLMainWrapper.h"

#import <SDL.h>
#import "KeyboardSupport.h"

#include <Limelight.h>

static void SendLowLevelKeyEvent(struct KeyEvent event) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if (event.modifier != 0) {
            LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_DOWN, event.modifier);
        }

        LiSendKeyboardEvent2(event.keycode, KEY_ACTION_DOWN, event.modifier, SS_KBE_FLAG_NON_NORMALIZED);
        usleep(50 * 1000);
        LiSendKeyboardEvent2(event.keycode, KEY_ACTION_UP, event.modifier, SS_KBE_FLAG_NON_NORMALIZED);

        if (event.modifier != 0) {
            LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_UP, event.modifier);
        }
    });
}

@implementation SDLMainWrapper

+ (void) setMainReady {
    SDL_SetMainReady();
}

+ (void)sendText:(NSString*)text {
    if (text.length == 0) {
        return;
    }

    BOOL canSendAsKeyEvents = YES;
    for (NSInteger index = 0; index < text.length; index++) {
        struct KeyEvent event = [KeyboardSupport translateKeyEvent:[text characterAtIndex:index] withModifierFlags:0];
        if (event.keycode == 0) {
            canSendAsKeyEvents = NO;
            break;
        }
    }

    if (!canSendAsKeyEvents) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            const char* utf8String = [text UTF8String];
            if (utf8String != NULL) {
                LiSendUtf8TextEvent(utf8String, (int)strlen(utf8String));
            }
        });
        return;
    }

    for (NSInteger index = 0; index < text.length; index++) {
        struct KeyEvent event = [KeyboardSupport translateKeyEvent:[text characterAtIndex:index] withModifierFlags:0];
        SendLowLevelKeyEvent(event);
    }
}

+ (void)sendBackspace {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        LiSendKeyboardEvent(0x08, KEY_ACTION_DOWN, 0);
        usleep(50 * 1000);
        LiSendKeyboardEvent(0x08, KEY_ACTION_UP, 0);
    });
}

+ (void)sendReturn {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        LiSendKeyboardEvent(0x0d, KEY_ACTION_DOWN, 0);
        usleep(50 * 1000);
        LiSendKeyboardEvent(0x0d, KEY_ACTION_UP, 0);
    });
}

@end
