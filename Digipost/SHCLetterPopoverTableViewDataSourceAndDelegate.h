//
//  SHCLetterPopoverTableViewDataSource.h
//  Digipost
//
//  Created by Håkon Bogen on 11.02.14.
//  Copyright (c) 2014 Shortcut. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SHCLetterPopoverTableViewDataSourceAndDelegate : NSObject<UITableViewDataSource,UITableViewDelegate>
@property (strong,nonatomic) NSArray *lineObjects;
@end
