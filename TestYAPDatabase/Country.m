//
//  Country.m
//  TestYAPDatabase
//
//  Created by  on 9/20/14.
//  Copyright (c) 2014 Delightful. All rights reserved.
//

#import "Country.h"

@implementation Country

+ (NSDictionary *)JSONKeyPathsByPropertyKey {
    return @{NSStringFromSelector(@selector(countryId)):@"id"};
}

@end
