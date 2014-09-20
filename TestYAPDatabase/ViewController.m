//
//  ViewController.m
//  TestYAPDatabase
//
//  Created by  on 9/20/14.
//  Copyright (c) 2014 Delightful. All rights reserved.
//

#import "ViewController.h"
#import "Country.h"

#import <YapDatabase.h>
#import <YapDatabaseView.h>

NSString *sortedCountriesViewName = @"sorted-countries";

@interface ViewController ()

@property (nonatomic, strong) YapDatabaseConnection *mainConnection;
@property (nonatomic, strong) YapDatabaseConnection *bgConnection;
@property (nonatomic, strong) YapDatabaseView *databaseView;
@property (nonatomic, strong) YapDatabaseViewMappings *mappings;
@property (nonatomic, strong) YapDatabase *database;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"List";
    [self.tableView setDelegate:self];
    [self.tableView setDataSource:self];
    
    [self setupDatabase];
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
                                                                             NSString *collection1, NSString *key1, id obj1,
                                                                             NSString *collection2, NSString *key2, id obj2){
        return [obj1 compare:obj2 options:NSCaseInsensitiveSearch];
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

#pragma mark - UITableViewDelegate

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self.mappings groupForSection:section];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self.mappings numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.mappings numberOfItemsInSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    
    __block Country *country = nil;
    //NSString *group = [self.mappings groupForSection:indexPath.section];
    [self.mainConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        country = [[transaction ext:sortedCountriesViewName] objectAtIndexPath:indexPath withMappings:self.mappings];
    }];
    
    [cell.textLabel setText:country.name];
    [cell.detailTextLabel setText:country.capitalCity];
    
    return cell;
}

@end
