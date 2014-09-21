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
#import "RegionHeader.h"

#import <YapDatabase.h>
#import <YapDatabaseView.h>
#import <AFNetworking.h>

NSString *sortedCountriesViewName = @"sorted-countries";
NSString *regionGroupedViewName = @"region-grouped-countries";
NSString *countriesCollectionName = @"countries";

@interface ViewController ()

@property (nonatomic, strong) YapDatabaseConnection *mainConnection;
@property (nonatomic, strong) YapDatabaseConnection *bgConnection;
@property (nonatomic, strong) YapDatabaseView *alphabeticalView;
@property (nonatomic, strong) YapDatabaseViewMappings *alphabeticalViewMappings;
@property (nonatomic, strong) YapDatabaseView *regionGroupView;
@property (nonatomic, strong) YapDatabaseViewMappings *regionGroupMappings;
@property (nonatomic, strong) YapDatabaseViewMappings *selectedMappings;
@property (nonatomic, strong) YapDatabase *database;
@property (nonatomic, assign) int page;
@property (nonatomic, assign) int totalCountries;
@property (nonatomic, assign, getter=isFetching) BOOL fetching;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Countries";
    
    UIBarButtonItem *regionButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Regions", nil) style:UIBarButtonItemStylePlain target:self action:@selector(didTapRegionButton:)];
    [self.navigationItem setRightBarButtonItem:regionButton];
    
    UIBarButtonItem *reverseButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Reverse", nil) style:UIBarButtonItemStylePlain target:self action:@selector(didTapReverseButton:)];
    [self.navigationItem setLeftBarButtonItem:reverseButton];
    
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

- (void)setSelectedMappings:(YapDatabaseViewMappings *)selectedMappings {
    if (_selectedMappings != selectedMappings) {
        _selectedMappings = selectedMappings;
        
        [self.mainConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [_selectedMappings updateWithTransaction:transaction];
        }];
        [self.tableView reloadData];
    }
}

- (void)didTapRegionButton:(id)sender {
    if (self.selectedMappings==self.alphabeticalViewMappings) {
        [self setSelectedMappings:self.regionGroupMappings];
        UIBarButtonItem *regionButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Alphabetical", nil) style:UIBarButtonItemStylePlain target:self action:@selector(didTapRegionButton:)];
        [self.navigationItem setRightBarButtonItem:regionButton];
    } else {
        [self setSelectedMappings:self.alphabeticalViewMappings];
        UIBarButtonItem *regionButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Regions", nil) style:UIBarButtonItemStylePlain target:self action:@selector(didTapRegionButton:)];
        [self.navigationItem setRightBarButtonItem:regionButton];
    }
}

- (void)didTapReverseButton:(id)sender {
    [self.mainConnection beginLongLivedReadTransaction];
    for (NSString *group in self.selectedMappings.allGroups) {
        [self.selectedMappings setIsReversed:![self.selectedMappings isReversedForGroup:group] forGroup:group];
    }
    [self.tableView reloadData];
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
    
    [self registerRegionGroupedView];
    [self registerAlphabeticalView];
    [self.mainConnection beginLongLivedReadTransaction];
    [self setSelectedMappings:self.alphabeticalViewMappings];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:self.database];
}

- (void)registerAlphabeticalView {
    YapDatabaseViewBlockType groupingBlockType = YapDatabaseViewBlockTypeWithObject;
    YapDatabaseViewGroupingWithObjectBlock groupingBlock = ^NSString *(NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[Country class]]) {
            Country *country = (Country *)object;
            if (country.name && country.name.length >= 1 && country.capitalCity.length > 0) {
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
    self.alphabeticalView = [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
                                                         groupingBlockType:groupingBlockType
                                                              sortingBlock:sortingBlock
                                                          sortingBlockType:sortingBlockType];
    [self.database registerExtension:self.alphabeticalView withName:sortedCountriesViewName];
    
    self.alphabeticalViewMappings = [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *group, YapDatabaseReadTransaction *transaction) {
        return YES;
    } sortBlock:^NSComparisonResult(NSString *group1, NSString *group2, YapDatabaseReadTransaction *transaction) {
        return [group1 compare:group2];
    } view:sortedCountriesViewName];
}

- (void)registerRegionGroupedView {
    YapDatabaseViewBlockType groupingBlockType = YapDatabaseViewBlockTypeWithObject;
    YapDatabaseViewGroupingWithObjectBlock groupingBlock = ^NSString *(NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[Country class]]) {
            Country *country = (Country *)object;
            if (country.regionName && country.regionName.length > 0 && country.capitalCity.length > 0) {
                return country.regionName;
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
    self.regionGroupView = [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
                                                         groupingBlockType:groupingBlockType
                                                              sortingBlock:sortingBlock
                                                          sortingBlockType:sortingBlockType];
    [self.database registerExtension:self.regionGroupView withName:regionGroupedViewName];
    
    self.regionGroupMappings = [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *group, YapDatabaseReadTransaction *transaction) {
        return YES;
    } sortBlock:^NSComparisonResult(NSString *group1, NSString *group2, YapDatabaseReadTransaction *transaction) {
        return [group1 compare:group2];
    } view:regionGroupedViewName];
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
    
    if (![[self.mainConnection ext:self.selectedMappings.view] hasChangesForNotifications:notifications]) {
        [self.mainConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.selectedMappings updateWithTransaction:transaction];
        }];
        return;
    }
    
    NSArray *sectionChanges = nil;
    NSArray *rowChanges = nil;
    
    [[self.mainConnection ext:self.selectedMappings.view] getSectionChanges:&sectionChanges
                                                              rowChanges:&rowChanges
                                                        forNotifications:notifications
                                                            withMappings:self.selectedMappings];
    if (sectionChanges.count == 0 && rowChanges.count == 0) {
        return;
    }
    
    NSInteger numberOfCountries = [self.selectedMappings numberOfItemsInAllGroups];
    if (numberOfCountries > 0) {
        self.title = [NSString stringWithFormat:NSLocalizedString(@"Countries (%d)", nil), (int)numberOfCountries];
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
                [self.tableView deleteRowsAtIndexPaths:@[rowChange.indexPath] withRowAnimation:UITableViewRowAnimationTop];
                break;
            }
            case YapDatabaseViewChangeInsert:{
                [self.tableView insertRowsAtIndexPaths:@[rowChange.newIndexPath] withRowAnimation:UITableViewRowAnimationTop];
                break;
            }
            case YapDatabaseViewChangeMove:{
                [self.tableView deleteRowsAtIndexPaths:@[rowChange.indexPath] withRowAnimation:UITableViewRowAnimationTop];
                [self.tableView insertRowsAtIndexPaths:@[rowChange.newIndexPath] withRowAnimation:UITableViewRowAnimationTop];
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

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView.contentOffset.y > scrollView.contentSize.height - scrollView.frame.size.height - scrollView.contentInset.top - 100) {
        [self fetchNext];
    }
}

#pragma mark - Networking

- (void)fetchCountries {
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    [manager setResponseSerializer:[AFJSONResponseSerializer serializerWithReadingOptions:0]];
    [manager GET:[NSString stringWithFormat:@"http://api.worldbank.org/countries?format=json&page=%d", self.page] parameters:nil success:^(AFHTTPRequestOperation *operation, NSArray *responseObject) {
        NSArray *countriesJSON = [responseObject lastObject];
        if (countriesJSON) {
            NSDictionary *info = [responseObject firstObject];
            self.totalCountries = [info[@"total"] intValue];
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
        self.fetching = NO;
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        self.fetching = NO;
        self.page--;
        self.page = MAX(self.page, 1);
        NSLog(@"Error: %@", error);
    }];
}

- (void)fetchNext {
    __block NSInteger totalCountriesFetched;
    [self.mainConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        totalCountriesFetched = [transaction numberOfKeysInCollection:countriesCollectionName];
    }];
    if (totalCountriesFetched < self.totalCountries && !self.isFetching) {
        self.fetching = YES;
        self.page++;
        [self fetchCountries];
    }
}

#pragma mark - UITableViewDelegate


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    __block Country *country = nil;
    //NSString *group = [self.mappings groupForSection:indexPath.section];
    [self.mainConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        country = [[transaction ext:self.selectedMappings.view] objectAtIndexPath:indexPath withMappings:self.selectedMappings];
    }];
    NSLog(@"Country: %@", country);
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    RegionHeader *header = [self regionHeaderForSection:section];
    [header setNeedsUpdateConstraints];
    [header updateConstraintsIfNeeded];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    RegionHeader *header = [self regionHeaderForSection:section];
    header.frame = ({CGRect frame = header.frame; frame.size.width = CGRectGetWidth(self.tableView.frame); frame;});
    [header setNeedsUpdateConstraints];
    [header updateConstraintsIfNeeded];
    [header setNeedsLayout];
    [header layoutIfNeeded];
    [header.regionNameLabel setPreferredMaxLayoutWidth:header.regionNameLabel.frame.size.width];
    [header setNeedsLayout];
    [header layoutIfNeeded];
    
    return [header systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    
}

- (RegionHeader *)regionHeaderForSection:(NSInteger)section {
    RegionHeader *header = (RegionHeader *)[[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([RegionHeader class]) owner:nil options:nil] firstObject];
    [header.regionNameLabel setText:[self.selectedMappings groupForSection:section]];
    return header;
}


#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self.selectedMappings numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.selectedMappings numberOfItemsInSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CountryCell *cell = (CountryCell *)[tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    
    __block Country *country = nil;
    [self.mainConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        country = [[transaction ext:self.selectedMappings.view] objectAtIndexPath:indexPath withMappings:self.selectedMappings];
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
