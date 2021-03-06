//
//  Country.h
//  TestYAPDatabase
//
//  Created by  on 9/20/14.
//  Copyright (c) 2014 Delightful. All rights reserved.
//

#import <MTLModel.h>
#import <MTLJSONAdapter.h>

@interface Country : MTLModel <MTLJSONSerializing>

@property (nonatomic, copy, readonly) NSString *countryId;
@property (nonatomic, copy, readonly) NSString *iso2Code;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *capitalCity;
@property (nonatomic, copy, readonly) NSString *regionId;
@property (nonatomic, copy, readonly) NSString *regionName;

- (BOOL)isEqualToCountry:(Country *)country;

@end
