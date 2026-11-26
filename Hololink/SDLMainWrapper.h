//
//  SDLMainWrapper.h
//  Moonlight
//
//  Created by Alex Haugland on 1/27/24.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

#ifndef SDLMainWrapper_h
#define SDLMainWrapper_h


#import "Foundation/Foundation.h"

@interface SDLMainWrapper: NSObject;


+ (void) setMainReady;
+ (void) sendText:(NSString*)text;
+ (void) sendBackspace;
+ (void) sendReturn;

@end

#endif /* SDLMainWrapper_h */
