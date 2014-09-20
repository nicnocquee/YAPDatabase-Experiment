//
//  ViewController.m
//  TestYAPDatabase
//
//  Created by  on 9/20/14.
//  Copyright (c) 2014 Delightful. All rights reserved.
//

#import "ViewController.h"
#import "Country.h"
#import "CountryCell.h"

#import <YapDatabase.h>
#import <YapDatabaseView.h>
#import <AFNetworking.h>

NSString *sortedCountriesViewName = @"sorted-countries";
NSString *countriesCollectionName = @"countries";

@interface ViewController ()

@property (nonatomic, strong) YapDatabaseConnection *mainConnection;
@property (nonatomic, strong) YapDatabaseConnection *bgConnection;
@property (nonatomic, strong) YapDatabaseView *databaseView;
@property (nonatomic, strong) YapDatabaseViewMappings *mappings;
@property (nonatomic, strong) YapDatabase *database;
@property (nonatomic, assign) int page;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Countries";
    
    [self.tableView registerNib:[UINib nibWithNibName:NSStringFromClass([CountryCell class]) bundle:nil] forCellReuseIdentifier:@"cell"];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 68;
    [self.tableView setDelegate:self];
    [self.tableView setDataSource:self];
    
    [self setupDatabase];
    
    self.page = 1;
    [self fetchCountries];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Database

- (void)setupDatabase {
    self.database = [[YapDatabase alloc] initWithPath:[self databasePath]];
    
    self.mainConnection = [self.database newConnection];
    self.bgConnection = [self.database newConnection];
    self.mainConnection.objectCacheLimit = 500; // increase object cache size
    self.mainConnection.metadataCacheEnabled = NO; // not using metadata on this connection
    [self.mainConnection beginLongLivedReadTransaction];
    
    self.bgConnection.objectCacheEnabled = NO; // don't need cache for write-only connection
    self.bgConnection.metadataCacheEnabled = NO;
    
    YapDatabaseViewBlockType groupingBlockType = YapDatabaseViewBlockTypeWithObject;
    YapDatabaseViewGroupingWithObjectBlock groupingBlock = ^NSString *(NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[Country class]]) {
            Country *country = (Country *)object;
            if (country.name && country.name.length >= 1) {
                return [country.name substringToIndex:1];
            }
        }
        return nil;
    };
    YapDatabaseViewBlockType sortingBlockType = YapDatabaseViewBlockTypeWithObject;
    YapDatabaseViewSortingWithObjectBlock sortingBlock = ^NSComparisonResult(NSString *group,
                                                                             NSString *collection1, NSString *key1, Country *obj1,
                                                                             NSString *collection2, NSString *key2, Country *obj2){
        return [obj1.name compare:obj2.name];
    };
    self.databaseView = [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
                                                     groupingBlockType:groupingBlockType
                                                          sortingBlock:sortingBlock
                                                      sortingBlockType:sortingBlockType];
    [self.database registerExtension:self.databaseView withName:sortedCountriesViewName];
    
    self.mappings = [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *group, YapDatabaseReadTransaction *transaction) {
        return YES;
    } sortBlock:^NSComparisonResult(NSString *group1, NSString *group2, YapDatabaseReadTransaction *transaction) {
        return [group1 compare:group2];
    } view:sortedCountriesViewName];
    
    [self.mainConnection beginLongLivedReadTransaction];
    [self.mainConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.mappings updateWithTransaction:transaction];
    }];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:self.database];
}

- (NSString *)databasePath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
    
    NSString *databaseName = @"database.sqlite";
    
    return [baseDir stringByAppendingPathComponent:databaseName];
}

- (void)yapDatabaseModified:(NSNotification *)notification {
    NSArray *notifications = [self.mainConnection beginLongLivedReadTransaction];
    
    if (![[self.mainConnection ext:sortedCountriesViewName] hasChangesForNotifications:notifications]) {
        [self.mainConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.mappings updateWithTransaction:transaction];
        }];
        return;
    }
    
    NSArray *sectionChanges = nil;
    NSArray *rowChanges = nil;
    
    [[self.mainConnection ext:sortedCountriesViewName] getSectionChanges:&sectionChanges
                                                              rowChanges:&rowChanges
                                                        forNotifications:notifications
                                                            withMappings:self.mappings];
    if (sectionChanges.count == 0 && rowChanges.count == 0) {
        return;
    }
    
    [self.tableView beginUpdates];
    
    for (YapDatabaseViewSectionChange *sectionChange in sectionChanges) {
        switch (sectionChange.type) {
            case YapDatabaseViewChangeDelete:{
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionChange.index] withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert:{
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionChange.index] withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            default:
                break;
        }
    }
    
    for (YapDatabaseViewRowChange *rowChange in rowChanges) {
        switch (rowChange.type) {
            case YapDatabaseViewChangeDelete:{
                [self.tableView deleteRowsAtIndexPaths:@[rowChange.indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert:{
                [self.tableView insertRowsAtIndexPaths:@[rowChange.newIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeMove:{
                [self.tableView deleteRowsAtIndexPaths:@[rowChange.indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertRowsAtIndexPaths:@[rowChange.newIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate:{
                [self.tableView reloadRowsAtIndexPaths:@[rowChange.indexPath] withRowAnimation:UITableViewRowAnimationNone];
                break;
            }
            default:
                break;
        }
    }
    
    [self.tableView endUpdates];
}

#pragma mark - Networking

- (void)fetchCountries {
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    [manager setResponseSerializer:[AFJSONResponseSerializer serializerWithReadingOptions:0]];
    [manager GET:[NSString stringWithFormat:@"http://api.worldbank.org/countries?format=json&page=%d", self.page] parameters:nil success:^(AFHTTPRequestOperation *operation, NSArray *responseObject) {
        NSArray *countriesJSON = [responseObject lastObject];
        if (countriesJSON) {
            NSLog(@"Got %lu countries", (unsigned long)countriesJSON.count);
            NSError *error;
            NSArray *countries = [MTLJSONAdapter modelsOfClass:[Country class] fromJSONArray:countriesJSON error:&error];
            if (!error) {
                [self.bgConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    for (Country *c in countries) {
                        [transaction setObject:c forKey:c.countryId inCollection:countriesCollectionName];
                    }
                } completionBlock:^{
                    NSLog(@"Done inserting to db");
                }];
            } else {
                NSLog(@"Error: %@", error);
            }
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
    }];
}

#pragma mark - UITableViewDelegate

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self.mappings groupForSection:section];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    __block Country *country = nil;
    //NSString *group = [self.mappings groupForSection:indexPath.section];
    [self.mainConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        country = [[transaction ext:sortedCountriesViewName] objectAtIndexPath:indexPath withMappings:self.mappings];
    }];
    NSLog(@"Country: %@", country);
}


#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self.mappings numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.mappings numberOfItemsInSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CountryCell *cell = (CountryCell *)[tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    
    __block Country *country = nil;
    [self.mainConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        country = [[transaction ext:sortedCountriesViewName] objectAtIndexPath:indexPath withMappings:self.mappings];
    }];
    
    [cell.countryNameLabel setText:country.name];
    if (country.capitalCity.length == 0) {
        UIFontDescriptor *userFont = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleCaption1];
        NSAttributedString *attr = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"No capital city", nil) attributes:@{NSFontAttributeName: [UIFont italicSystemFontOfSize:userFont.pointSize]}];
        [cell.capitalCityLabel setAttributedText:attr];
    } else {
        [cell.capitalCityLabel setText:country.capitalCity];
    }
    
    [cell setNeedsUpdateConstraints];
    [cell updateConstraintsIfNeeded];
    
    return cell;
}

@end
