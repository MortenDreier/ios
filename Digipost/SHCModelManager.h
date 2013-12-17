//
//  SHCModelManager.h
//  Digipost
//
//  Created by Eivind Bohler on 11.12.13.
//  Copyright (c) 2013 Shortcut. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class SHCFolder;

@interface SHCModelManager : NSObject

@property (strong, nonatomic, readonly) NSManagedObjectContext *managedObjectContext;

+ (instancetype)sharedManager;

- (void)updateRootResourceWithAttributes:(NSDictionary *)attributes;
- (void)updateDocumentsInFolder:(SHCFolder *)folder withAttributes:(NSDictionary *)attributes;
- (NSEntityDescription *)rootResourceEntity;
- (NSEntityDescription *)mailboxEntity;
- (NSEntityDescription *)folderEntity;
- (NSEntityDescription *)documentEntity;
- (NSEntityDescription *)attachmentEntity;
- (NSDate *)rootResourceCreatedAt;

@end