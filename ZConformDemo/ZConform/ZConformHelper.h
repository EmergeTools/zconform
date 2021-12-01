//
//  ZConformHelper.h
//  ZConformDemo
//
//  Created by Noah Martin on 11/30/21.
//

#ifndef ZConformHelper_h
#define ZConformHelper_h

#import <Foundation/Foundation.h>

@interface ZConformHelper : NSObject

+ (void)setup;

+ (BOOL)contains:(NSNumber * _Nonnull)address conformingTo:(NSNumber * _Nonnull)protocolAddress;

@end

#endif /* ZConformHelper_h */
