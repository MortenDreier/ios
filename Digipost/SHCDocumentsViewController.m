//
//  SHCDocumentsViewController.m
//  Digipost
//
//  Created by Eivind Bohler on 16.12.13.
//  Copyright (c) 2013 Shortcut. All rights reserved.
//

#import <UIAlertView+Blocks.h>
#import <AFNetworking/AFURLConnectionOperation.h>
#import <UIActionSheet+Blocks.h>
#import "SHCDocumentsViewController.h"
#import "SHCModelManager.h"
#import "SHCDocument.h"
#import "SHCDocumentTableViewCell.h"
#import "SHCAttachment.h"
#import "SHCAPIManager.h"
#import "SHCRootResource.h"
#import "SHCFolder.h"
#import "NSError+ExtraInfo.h"
#import "SHCAttachmentsViewController.h"
#import "SHCLetterViewController.h"
#import "SHCAppDelegate.h"
#import "UIViewController+ValidateOpening.h"
#import "SHCInvoice.h"
#import "SHCUploadTableViewCell.h"

// Segue identifiers (to enable programmatic triggering of segues)
NSString *const kPushDocumentsIdentifier = @"PushDocuments";

// Google Analytics screen name
NSString *const kDocumentsViewControllerScreenName = @"Documents";

@interface SHCDocumentsViewController ()

@property (weak, nonatomic) IBOutlet UIBarButtonItem *selectionBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *moveBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *deleteBarButtonItem;
@property (weak, nonatomic) IBOutlet UIView *tableViewBackgroundView;
@property (weak, nonatomic) IBOutlet UILabel *noDocumentsLabel;
@property (copy, nonatomic) NSString *selectedDocumentUpdateUri;

@end

@implementation SHCDocumentsViewController

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [self.navigationController.toolbar setBarTintColor:[UIColor colorWithRed:64.0/255.0 green:66.0/255.0 blue:69.0/255.0 alpha:0.95]];

    self.selectionBarButtonItem.title = NSLocalizedString(@"DOCUMENTS_VIEW_CONTROLLER_TOOLBAR_SELECT_ALL_TITLE", @"Select all");
    self.moveBarButtonItem.title = NSLocalizedString(@"DOCUMENTS_VIEW_CONTROLLER_TOOLBAR_MOVE_TITLE", @"Move");
    self.deleteBarButtonItem.title = NSLocalizedString(@"DOCUMENTS_VIEW_CONTROLLER_TOOLBAR_DELETE_TITLE", @"Delete");

    self.baseEntity = [[SHCModelManager sharedManager] documentEntity];
    self.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(createdAt))
                                                           ascending:NO
                                                            selector:@selector(compare:)]];
    self.predicate = [NSPredicate predicateWithFormat:@"%K == %@",
                      [NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(folder)), NSStringFromSelector(@selector(name))],
                      self.folderName];

    self.screenName = kDocumentsViewControllerScreenName;

    [super viewDidLoad];

    [self updateToolbarButtonItems];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self.navigationController setToolbarHidden:YES animated:NO];

    if ([self.folderName isEqualToString:kFolderArchiveName]) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(uploadProgressDidChange:) name:kAPIManagerUploadProgressChangedNotificationName object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(uploadProgressDidFinish:) name:kAPIManagerUploadProgressFinishedNotificationName object:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self updateContentsFromServer];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[SHCAPIManager sharedManager] cancelUpdatingDocuments];

    if ([self.folderName isEqualToString:kFolderArchiveName]) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kAPIManagerUploadProgressChangedNotificationName object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kAPIManagerUploadProgressFinishedNotificationName object:nil];
    }

    [self programmaticallyEndRefresh];

    [super viewWillDisappear:animated];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:kPushAttachmentsIdentifier]) {
        SHCDocument *document = (SHCDocument *)sender;
        self.selectedDocumentUpdateUri = document.updateUri;

        SHCAttachmentsViewController *attachmentsViewController = (SHCAttachmentsViewController *)segue.destinationViewController;
        attachmentsViewController.documentsViewController = self;
        attachmentsViewController.attachments = document.attachments;
    } else if ([segue.identifier isEqualToString:kPushLetterIdentifier]) {
        SHCAttachment *attachment = (SHCAttachment *)sender;

        SHCLetterViewController *letterViewController = (SHCLetterViewController *)segue.destinationViewController;
        letterViewController.documentsViewController = self;
        letterViewController.attachment = attachment;
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    [super setEditing:editing animated:animated];

    [self.navigationController setToolbarHidden:!editing animated:animated];

    [self updateNavbar];

    self.navigationController.interactivePopGestureRecognizer.enabled = !editing;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    NSInteger number = [super numberOfSectionsInTableView:tableView];

    if (number == 0) {
        [self showTableViewBackgroundView:YES];
    }

    return number;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger number = [super tableView:tableView numberOfRowsInSection:section];

    if ([self.folderName isEqualToString:kFolderArchiveName] && [SHCAPIManager sharedManager].isUploadingFile) {
        number++;
    }

    [self showTableViewBackgroundView:(number == 0)];

    return number;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.folderName isEqualToString:kFolderArchiveName] && [SHCAPIManager sharedManager].isUploadingFile) {

        if (indexPath.row == 0) {
            SHCUploadTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kUploadTableViewCellIdentifier forIndexPath:indexPath];
            cell.progressView.progress = [SHCAPIManager sharedManager].uploadProgress.fractionCompleted;
            cell.dateLabel.text = [SHCDocument stringForDocumentDate:[NSDate date]];
            cell.fileNameLabel.text = [[SHCAPIManager sharedManager].uploadProgress userInfo][@"fileName"];

            return cell;
        }

        // If we have a cell displaying the upload progress, adjust the indexPath accordingly.
        indexPath = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];
    }

    SHCDocument *document = [self.fetchedResultsController objectAtIndexPath:indexPath];

    SHCDocumentTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDocumentTableViewCellIdentifier forIndexPath:indexPath];

    SHCAttachment *attachment = [document mainDocumentAttachment];

    if ([attachment.authenticationLevel isEqualToString:kAttachmentOpeningValidAuthenticationLevel]) {
        cell.unreadImageView.hidden = [attachment.read boolValue];
        cell.lockedImageView.hidden = YES;
    } else {
        cell.unreadImageView.hidden = YES;
        cell.lockedImageView.hidden = NO;
    }
    cell.attachmentImageView.hidden = [document.attachments count] > 1 ? NO : YES;
    cell.senderLabel.text = attachment.document.creatorName;
    cell.dateLabel.text = [SHCDocument stringForDocumentDate:attachment.document.createdAt];
    cell.subjectLabel.text = attachment.subject;

    return cell;
}

#pragma mark - UITableViewDelegate

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.isEditing) {
        [self updateToolbarButtonItems];

        return;
    }
    
    SHCDocument *document = [self.fetchedResultsController objectAtIndexPath:indexPath];

    if ([document.attachments count] > 1) {
        [self performSegueWithIdentifier:kPushAttachmentsIdentifier sender:document];
    } else {

        SHCAttachment *attachment = [document.attachments firstObject];

        [self validateOpeningAttachment:attachment success:^{
            if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
                ((SHCAppDelegate *)[UIApplication sharedApplication].delegate).letterViewController.attachment = attachment;
            } else {
                [self performSegueWithIdentifier:kPushLetterIdentifier sender:attachment];
            }
        } failure:^(NSError *error) {
            [UIAlertView showWithTitle:error.errorTitle
                               message:[error localizedDescription]
                     cancelButtonTitle:nil
                     otherButtonTitles:@[error.okButtonTitle]
                              tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
                                  [tableView deselectRowAtIndexPath:indexPath animated:YES];
                              }];
        }];
    }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.isEditing) {
        [self updateToolbarButtonItems];

        return;
    }
}

#pragma mark - IBActions

- (IBAction)didTapSelectionBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    if ([self someRowsSelected]) {
        [self deselectAllRows];
    } else {
        [self selectAllRows];
    }

    [self updateToolbarButtonItems];
}

- (IBAction)didTapMoveBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    NSMutableArray *destinations = [NSMutableArray array];
    if (![[self.folderName lowercaseString] isEqualToString:[kFolderInboxName lowercaseString]]) {
        [destinations addObject:kFolderInboxName];
    }
    if (![[self.folderName lowercaseString] isEqualToString:[kFolderWorkAreaName lowercaseString]]) {
        [destinations addObject:kFolderWorkAreaName];
    }
    if (![[self.folderName lowercaseString] isEqualToString:[kFolderArchiveName lowercaseString]]) {
        [destinations addObject:kFolderArchiveName];
    }

    [UIActionSheet showFromBarButtonItem:barButtonItem
                                animated:YES
                               withTitle:nil
                       cancelButtonTitle:NSLocalizedString(@"GENERIC_CANCEL_BUTTON_TITLE", @"Cancel")
                  destructiveButtonTitle:nil
                       otherButtonTitles:destinations
                                tapBlock:^(UIActionSheet *actionSheet, NSInteger buttonIndex) {
                                    if (buttonIndex < [destinations count]) {
                                        NSString *location = [destinations[buttonIndex] uppercaseString];

                                        [self moveSelectedDocumentsToLocation:location];
                                    }
                                }];
}

- (IBAction)didTapDeleteBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    NSUInteger numberOfLetters = [[self.tableView indexPathsForSelectedRows] count];
    NSString *letterWord = numberOfLetters == 1 ? NSLocalizedString(@"DOCUMENTS_VIEW_CONTROLLER_DELETE_CONFIRMATION_TWO_SINGULAR", @"letter") :
                                                  NSLocalizedString(@"DOCUMENTS_VIEW_CONTROLLER_DELETE_CONFIRMATION_TWO_PLURAL", @"letters");

    NSString *deleteString = [NSString stringWithFormat:@"%@ %lu %@",
                              NSLocalizedString(@"DOCUMENTS_VIEW_CONTROLLER_DELETE_CONFIRMATION_ONE", @"Delete"),
                              (unsigned long)[[self.tableView indexPathsForSelectedRows] count],
                              letterWord];

    [UIActionSheet showFromBarButtonItem:barButtonItem
                                animated:YES
                               withTitle:nil
                       cancelButtonTitle:NSLocalizedString(@"GENERIC_CANCEL_BUTTON_TITLE", @"Cancel")
                  destructiveButtonTitle:deleteString
                       otherButtonTitles:nil
                                tapBlock:^(UIActionSheet *actionSheet, NSInteger buttonIndex) {
                                    if (buttonIndex == 0) {
                                        [self deleteDocuments];
                                    }
                                }];
}

#pragma mark - Private methods

- (void)updateContentsFromServer
{
    if ([SHCAPIManager sharedManager].isUpdatingDocuments) {
        return;
    }

    [[SHCAPIManager sharedManager] updateDocumentsInFolderWithName:self.folderName folderUri:self.folderUri success:^{
        [self updateFetchedResultsController];
        [self programmaticallyEndRefresh];
        [self updateNavbar];
        
        // If the user has just managed to enter a document with attachments _after_ the API call finished,
        // but _before_ the Core Data stuff has finished, tapping an attachment will cause the app to crash.
        // To avoid this, let's check if the attachment vc is on top of the nav stack, and if it is - repopulate its data.
        if ([self.navigationController.topViewController isKindOfClass:[SHCAttachmentsViewController class]]) {
            SHCAttachmentsViewController *attachmentsViewController = (SHCAttachmentsViewController *)self.navigationController.topViewController;

            SHCDocument *selectedDocument = [SHCDocument existingDocumentWithUpdateUri:self.selectedDocumentUpdateUri inManagedObjectContext:[SHCModelManager sharedManager].managedObjectContext];

            attachmentsViewController.attachments = selectedDocument.attachments;
        }

        SHCRootResource *rootResource = [SHCRootResource existingRootResourceInManagedObjectContext:[SHCModelManager sharedManager].managedObjectContext];
        if (!rootResource.currentBankAccount) {

            if ([self documentsNeedCurrentBankAccount]) {

                [self updateCurrentBankAccountWithUri:rootResource.currentBankAccountUri];
            }
        }
    } failure:^(NSError *error) {

        NSHTTPURLResponse *response = [error userInfo][AFNetworkingOperationFailingURLResponseErrorKey];
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            if ([[SHCAPIManager sharedManager] responseCodeIsUnauthorized:response]) {
                // We were unauthorized, due to the session being invalid.
                // Let's retry in the next run loop
                [self performSelector:@selector(updateContentsFromServer) withObject:nil afterDelay:0.0];

                return;
            }
        }

        [self programmaticallyEndRefresh];

        [UIAlertView showWithTitle:error.errorTitle
                           message:[error localizedDescription]
                 cancelButtonTitle:nil
                 otherButtonTitles:@[error.okButtonTitle]
                          tapBlock:error.tapBlock];
    }];
}

- (void)updateNavbar
{
    [super updateNavbar];

    self.navigationItem.title = self.folderName;

    UIBarButtonItem *rightBarButtonItem = nil;
    if ([self numberOfRows] > 0) {
        rightBarButtonItem = self.editButtonItem;
    }

    self.navigationItem.rightBarButtonItem = rightBarButtonItem;
}

- (void)updateToolbarButtonItems
{
    if ([self.tableView indexPathsForSelectedRows] > 0) {
        self.moveBarButtonItem.enabled = YES;
        self.deleteBarButtonItem.enabled = YES;
    } else {
        self.moveBarButtonItem.enabled = NO;
        self.deleteBarButtonItem.enabled = NO;
    }

    if ([self someRowsSelected]) {
        self.selectionBarButtonItem.title = NSLocalizedString(@"DOCUMENTS_VIEW_CONTROLLER_TOOLBAR_SELECT_NONE_TITLE", @"Select none");
    } else {
        self.selectionBarButtonItem.title = NSLocalizedString(@"DOCUMENTS_VIEW_CONTROLLER_TOOLBAR_SELECT_ALL_TITLE", @"Select all");
    }
}

- (BOOL)someRowsSelected
{
    return [[self.tableView indexPathsForSelectedRows] count] > 0;
}

- (NSInteger)numberOfRows
{
    NSInteger numberOfRows = 0;
    for (NSInteger section = 0; section < [self.tableView numberOfSections]; section++) {
        numberOfRows += [self.tableView numberOfRowsInSection:section];
    }

    return numberOfRows;
}

- (void)selectAllRows
{
    for (NSInteger section = 0; section < [self.tableView numberOfSections]; section++) {
        for (NSInteger row = 0; row < [self.tableView numberOfRowsInSection:section]; row++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
            [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        }
    }
}

- (void)deselectAllRows
{
    for (NSIndexPath *indexPath in [self.tableView indexPathsForVisibleRows]) {
        SHCDocumentTableViewCell *cell = (SHCDocumentTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }

    for (NSIndexPath *indexPath in [self.tableView indexPathsForSelectedRows]) {
        [self.tableView deselectRowAtIndexPath:indexPath animated:NO];
    }
}

- (void)moveSelectedDocumentsToLocation:(NSString *)location
{
    for (NSIndexPath *indexPathOfSelectedRow in [self.tableView indexPathsForSelectedRows]) {
        SHCDocument *document = [self.fetchedResultsController objectAtIndexPath:indexPathOfSelectedRow];

        [self moveDocument:document toLocation:location];
    }

    [self deselectAllRows];
    [self updateToolbarButtonItems];
}

- (void)moveDocument:(SHCDocument *)document toLocation:(NSString *)location
{
    [[SHCAPIManager sharedManager] moveDocument:document toLocation:location withSuccess:^{
        [self updateFetchedResultsController];
    } failure:^(NSError *error) {

        NSHTTPURLResponse *response = [error userInfo][AFNetworkingOperationFailingURLResponseErrorKey];
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            if ([[SHCAPIManager sharedManager] responseCodeIsUnauthorized:response]) {
                // We were unauthorized, due to the session being invalid.
                // Let's retry in the next run loop
                double delayInSeconds = 0.0;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                    [self moveDocument:document toLocation:location];
                });

                return;
            }
        }

        [UIAlertView showWithTitle:error.errorTitle
                           message:[error localizedDescription]
                 cancelButtonTitle:nil
                 otherButtonTitles:@[error.okButtonTitle]
                          tapBlock:error.tapBlock];
    }];
}

- (void)deleteDocuments
{
    for (NSIndexPath *indexPathOfSelectedRow in [self.tableView indexPathsForSelectedRows]) {
        SHCDocument *document = [self.fetchedResultsController objectAtIndexPath:indexPathOfSelectedRow];

        [self deleteDocument:document];
    }

    [self deselectAllRows];
    [self updateToolbarButtonItems];
}

- (void)deleteDocument:(SHCDocument *)document
{
    [[SHCAPIManager sharedManager] deleteDocument:document withSuccess:^{
        [self updateFetchedResultsController];
    } failure:^(NSError *error) {

        NSHTTPURLResponse *response = [error userInfo][AFNetworkingOperationFailingURLResponseErrorKey];
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            if ([[SHCAPIManager sharedManager] responseCodeIsUnauthorized:response]) {
                // We were unauthorized, due to the session being invalid.
                // Let's retry in the next run loop
                [self performSelector:@selector(deleteDocument:) withObject:document afterDelay:0.0];

                return;
            }
        }

        [UIAlertView showWithTitle:error.errorTitle
                           message:[error localizedDescription]
                 cancelButtonTitle:nil
                 otherButtonTitles:@[error.okButtonTitle]
                          tapBlock:error.tapBlock];
    }];
}

- (BOOL)documentsNeedCurrentBankAccount
{
    NSManagedObjectContext *managedObjectContext = [SHCModelManager sharedManager].managedObjectContext;

    for (SHCDocument *document in [SHCDocument allDocumentsInFolderWithName:self.folderName inManagedObjectContext:managedObjectContext]) {
        for (SHCAttachment *attachment in document.attachments) {
            if (attachment.invoice && [attachment.invoice.canBePaidByUser boolValue] && [attachment.invoice.sendToBankUri length] > 0) {
                return YES;
            }
        }
    }

    return NO;
}

- (void)updateCurrentBankAccountWithUri:(NSString *)uri
{
    if ([SHCAPIManager sharedManager].isUpdatingBankAccount) {
        return;
    }

    [[SHCAPIManager sharedManager] updateBankAccountWithUri:uri success:nil failure:^(NSError *error) {

        NSHTTPURLResponse *response = [error userInfo][AFNetworkingOperationFailingURLResponseErrorKey];
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            if ([[SHCAPIManager sharedManager] responseCodeIsUnauthorized:response]) {
                // We were unauthorized, due to the session being invalid.
                // Let's retry in the next run loop
                double delayInSeconds = 0.0;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                    [self updateCurrentBankAccountWithUri:uri];
                });

                return;
            }
        }

        [UIAlertView showWithTitle:error.errorTitle
                           message:[error localizedDescription]
                 cancelButtonTitle:nil
                 otherButtonTitles:@[error.okButtonTitle]
                          tapBlock:error.tapBlock];
    }];
}

- (void)uploadProgressDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{

        // Don't do anything if this view controller isn't visible
        if (!(self.isViewLoaded && self.view.window)) {
            return;
        }

        // Try to find our upload cell
        SHCUploadTableViewCell *uploadCell = nil;

        for (UITableViewCell *cell in [self.tableView visibleCells]) {
            if ([cell isKindOfClass:[SHCUploadTableViewCell class]]) {
                uploadCell = (SHCUploadTableViewCell *)cell;
                break;
            }
        }

        if (uploadCell) {
            uploadCell.progressView.progress = [SHCAPIManager sharedManager].uploadProgress.fractionCompleted;
            NSLog(@"fractionCompleted = %f", [SHCAPIManager sharedManager].uploadProgress.fractionCompleted);
        } else {
            // We've not found the upload cell - let's check if the topmost cell is visible.
            // If it is, that means we're missing the upload cell and we need to insert it.
            NSIndexPath *firstIndexPath = [NSIndexPath indexPathForRow:0 inSection:0];
            if ([[self.tableView indexPathsForVisibleRows] containsObject:firstIndexPath]) {
                [self.tableView reloadData];
            }
        }
    });
}

- (void)uploadProgressDidFinish:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Don't do anything if this view controller isn't visible
        if (!(self.isViewLoaded && self.view.window)) {
            return;
        }

        [self updateContentsFromServer];
    });
}

- (void)showTableViewBackgroundView:(BOOL)showTableViewBackgroundView
{
    if (!self.tableViewBackgroundView.superview) {
        self.tableView.backgroundView = self.tableViewBackgroundView;

        NSString *format = NSLocalizedString(@"DOCUMENTS_VIEW_CONTROLLER_NO_DOCUMENTS_TITLE", @"You have no letters in the folder %@.");
        self.noDocumentsLabel.text = [NSString stringWithFormat:format, self.folderName];
    }

    self.tableViewBackgroundView.hidden = !showTableViewBackgroundView;
}

@end
