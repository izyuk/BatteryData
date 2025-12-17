//
//  ObjCExceptionCatcher.m
//  BatteryData
//
//  Created by Dmytro Izyuk on 17.12.2025.
//

#import "ObjCExceptionCatcher.h"

@implementation _ObjCExceptionCatcher

+ (id)catch:(id(^)(void))tryBlock {
    @try {
        return tryBlock();
    }
    @catch (NSException *exception) {
        return nil;
    }
}

@end
