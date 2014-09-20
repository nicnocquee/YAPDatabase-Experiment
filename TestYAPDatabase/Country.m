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
    return @{NSStringFromSelector(@selector(countryId)):@"id",
             NSStringFromSelector(@selector(regionId)):@"region.id",
             NSStringFromSelector(@selector(regionName)):@"region.value",
             };
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[Country class]]) {
        return NO;
    }
    return [self isEqualToCountry:object];
}

- (BOOL)isEqualToCountry:(Country *)country {
    return  [self.countryId isEqualToString:country.countryId] &&
            [self.iso2Code isEqualToString:country.iso2Code] &&
            [self.name isEqualToString:country.name] &&
            [self.capitalCity isEqualToString:country.capitalCity]
    ;
}

- (NSUInteger)hash {
    return self.countryId.hash & self.iso2Code.hash & self.name.hash & self.capitalCity.hash;
}

@end
