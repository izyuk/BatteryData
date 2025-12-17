//
//  ObjCExceptionCatcher.h
//  BatteryData
//
//  Created by Dmytro Izyuk on 17.12.2025.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface _ObjCExceptionCatcher : NSObject
+ (id)catch:(id(^)(void))tryBlock;
@end

NS_ASSUME_NONNULL_END
