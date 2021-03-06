//
//  RoomsTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "RoomsTableViewController.h"

#import "AFNetworking.h"
#import "CallViewController.h"
#import "AddParticipantsTableViewController.h"
#import "RoomTableViewCell.h"
#import "CCCertificate.h"
#import "NCAPIController.h"
#import "NCImageSessionManager.h"
#import "NCConnectionController.h"
#import "NCPushNotification.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NSDate+DateTools.h"
#import "UIImageView+Letters.h"
#import "AFImageDownloader.h"
#import "UIImageView+AFNetworking.h"
#import "NCChatViewController.h"
#import "NCRoomsManager.h"
#import "NewRoomTableViewController.h"
#import "RoundedNumberView.h"
#import "PlaceholderView.h"

typedef void (^FetchRoomsCompletionBlock)(BOOL success);

@interface RoomsTableViewController () <CCCertificateDelegate>
{
    NSMutableArray *_rooms;
    UIRefreshControl *_refreshControl;
    BOOL _allowEmptyGroupRooms;
    PlaceholderView *_roomsBackgroundView;
}

@end

@implementation RoomsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    _rooms = [[NSMutableArray alloc] init];
    
    [self createRefreshControl];
    
    AFImageDownloader *imageDownloader = [[AFImageDownloader alloc]
                                          initWithSessionManager:[NCImageSessionManager sharedInstance]
                                          downloadPrioritization:AFImageDownloadPrioritizationFIFO
                                          maximumActiveDownloads:4
                                          imageCache:[[AFAutoPurgingImageCache alloc] init]];
    
    [UIImageView setSharedImageDownloader:imageDownloader];
    
    UIImage *navigationLogo = [UIImage imageNamed:@"navigationLogo"];
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:navigationLogo];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    // Rooms placeholder view
    _roomsBackgroundView = [[PlaceholderView alloc] init];
    [_roomsBackgroundView.placeholderImage setImage:[UIImage imageNamed:@"conversations-placeholder"]];
    [_roomsBackgroundView.placeholderText setText:@"You are not part of any conversation. Press + to start a new one."];
    [_roomsBackgroundView.placeholderView setHidden:YES];
    [_roomsBackgroundView.loadingView startAnimating];
    self.tableView.backgroundView = _roomsBackgroundView;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(serverCapabilitiesReceived:) name:NCServerCapabilitiesReceivedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStateHasChanged:) name:NCAppStateHasChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NCConnectionStateHasChangedNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self adaptInterfaceForAppState:[NCConnectionController sharedInstance].appState];
    [self adaptInterfaceForConnectionState:[NCConnectionController sharedInstance].connectionState];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Notifications

- (void)serverCapabilitiesReceived:(NSNotification *)notification
{
    // If the logged-in user is using an old NC Talk version on the server then logged the user out.
    if (![[NCSettingsController sharedInstance] serverUsesRequiredTalkVersion]) {
        [[NCSettingsController sharedInstance] logoutWithCompletionBlock:^(NSError *error) {
            [[NCUserInterfaceController sharedInstance] presentConversationsViewController];
            [[NCConnectionController sharedInstance] checkAppState];
        }];
    }
}

- (void)appStateHasChanged:(NSNotification *)notification
{
    AppState appState = [[notification.userInfo objectForKey:@"appState"] intValue];
    [self adaptInterfaceForAppState:appState];
}

- (void)connectionStateHasChanged:(NSNotification *)notification
{
    ConnectionState connectionState = [[notification.userInfo objectForKey:@"connectionState"] intValue];
    [self adaptInterfaceForConnectionState:connectionState];
}

#pragma mark - Interface Builder Actions

- (IBAction)addButtonPressed:(id)sender
{
    NewRoomTableViewController *newRoowVC = [[NewRoomTableViewController alloc] init];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:newRoowVC];
    [self presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark - Refresh Control

- (void)createRefreshControl
{
    _refreshControl = [UIRefreshControl new];
    _refreshControl.tintColor = [UIColor colorWithWhite:0 alpha:0.3];
    _refreshControl.backgroundColor = [UIColor colorWithRed:0.94 green:0.94 blue:0.96 alpha:1.0]; //efeff4
    [_refreshControl addTarget:self action:@selector(refreshControlTarget) forControlEvents:UIControlEventValueChanged];
    [self setRefreshControl:_refreshControl];
}

- (void)deleteRefreshControl
{
    [_refreshControl endRefreshing];
    self.refreshControl = nil;
}

- (void)refreshControlTarget
{
    [self fetchRoomsWithCompletionBlock:nil];
    
    // Actuate `Peek` feedback (weak boom)
    AudioServicesPlaySystemSound(1519);
}

#pragma mark - User Interface

- (void)adaptInterfaceForAppState:(AppState)appState
{
    switch (appState) {
        case kAppStateReady:
        {
            [self fetchRoomsWithCompletionBlock:nil];
        }
            break;
            
        default:
            break;
    }
}

- (void)adaptInterfaceForConnectionState:(ConnectionState)connectionState
{
    switch (connectionState) {
        case kConnectionStateConnected:
        {
            [self setOnlineAppearance];
        }
            break;
            
        case kConnectionStateDisconnected:
        {
            [self setOfflineAppearance];
        }
            break;
            
        default:
            break;
    }
}

- (void)setOfflineAppearance
{
    self.addButton.enabled = NO;
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"navigationLogoOffline"]];
}

- (void)setOnlineAppearance
{
    self.addButton.enabled = YES;
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"navigationLogo"]];
}

#pragma mark - Rooms

- (void)fetchRoomsWithCompletionBlock:(FetchRoomsCompletionBlock)block
{
    [[NCAPIController sharedInstance] getRoomsWithCompletionBlock:^(NSMutableArray *rooms, NSError *error, NSInteger statusCode) {
        if (!error) {
            _rooms = rooms;
            [_roomsBackgroundView.loadingView stopAnimating];
            [_roomsBackgroundView.loadingView setHidden:YES];
            [_roomsBackgroundView.placeholderView setHidden:(rooms.count > 0)];
            [self.tableView reloadData];
            NSLog(@"Rooms updated");
            if (block) {
                block(YES);
            }
        } else {
            NSLog(@"Error while trying to get rooms: %@", error);
            if ([error code] == NSURLErrorServerCertificateUntrusted) {
                NSLog(@"Untrusted certificate");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[CCCertificate sharedManager] presentViewControllerCertificateWithTitle:[error localizedDescription] viewController:self delegate:self];
                });
                
            }
            if (block) {
                block(NO);
            }
        }
        
        [_refreshControl endRefreshing];
    }];
}

- (void)trustedCerticateAccepted
{
    [self fetchRoomsWithCompletionBlock:nil];
}

- (NCRoom *)getRoomForToken:(NSString *)token
{
    NCRoom *room = nil;
    for (NCRoom *localRoom in _rooms) {
        if (localRoom.token == token) {
            room = localRoom;
        }
    }
    return room;
}

- (NCRoom *)getRoomForId:(NSInteger)roomId
{
    NCRoom *room = nil;
    for (NCRoom *localRoom in _rooms) {
        if (localRoom.roomId == roomId) {
            room = localRoom;
        }
    }
    return room;
}

#pragma mark - Room actions

- (void)addParticipantInRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    AddParticipantsTableViewController *addParticipantsVC = [[AddParticipantsTableViewController alloc] initForRoom:room];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:addParticipantsVC];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)renameRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    UIAlertController *renameDialog =
    [UIAlertController alertControllerWithTitle:@"Enter conversation name:"
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    [renameDialog addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Conversation name";
        textField.text = room.name;
        textField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
        textField.autocorrectionType = UITextAutocorrectionTypeDefault;
    }];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newRoomName = [[renameDialog textFields][0] text];
        NSString *trimmedName = [newRoomName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [[NCAPIController sharedInstance] renameRoom:room.token withName:trimmedName andCompletionBlock:^(NSError *error) {
            if (!error) {
                [self fetchRoomsWithCompletionBlock:nil];
            } else {
                NSLog(@"Error renaming the room: %@", error.description);
                //TODO: Error handling
            }
        }];
    }];
    [renameDialog addAction:confirmAction];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [renameDialog addAction:cancelAction];
    
    [self presentViewController:renameDialog animated:YES completion:nil];
}

- (void)shareLinkFromRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    NSString *shareMessage = [NSString stringWithFormat:@"Join the conversation at %@/index.php/call/%@",
                              [[NCAPIController sharedInstance] currentServerUrl], room.token];
    if (room.name && ![room.name isEqualToString:@""]) {
        shareMessage = [NSString stringWithFormat:@"Join the conversation%@ at %@/index.php/call/%@",
                        [NSString stringWithFormat:@" \"%@\"", room.name], [[NCAPIController sharedInstance] currentServerUrl], room.token];
    }
    NSArray *items = @[shareMessage];
    UIActivityViewController *controller = [[UIActivityViewController alloc]initWithActivityItems:items applicationActivities:nil];
    
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    NSString *emailSubject = [NSString stringWithFormat:@"%@ invitation", appDisplayName];
    [controller setValue:emailSubject forKey:@"subject"];

    // Presentation on iPads
    controller.popoverPresentationController.sourceView = self.tableView;
    controller.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:controller animated:YES completion:nil];
    
    controller.completionWithItemsHandler = ^(NSString *activityType,
                                              BOOL completed,
                                              NSArray *returnedItems,
                                              NSError *error) {
        if (error) {
            NSLog(@"An Error occured sharing room: %@, %@", error.localizedDescription, error.localizedFailureReason);
        }
    };
}

- (void)makePublicRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    [[NCAPIController sharedInstance] makeRoomPublic:room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            NSString *title = [NSString stringWithFormat:@"%@ is now public", room.name];
            // Room type condition should be removed when we don't set room names by default on OneToOne calls.
            if (room.type == kNCRoomTypeOneToOneCall || !room.name || [room.name isEqualToString:@""]) {
                title = @"This conversation is now public";
            }
            [self showShareDialogForRoom:room withTitle:title];
            [self fetchRoomsWithCompletionBlock:nil];
        } else {
            NSLog(@"Error making public the room: %@", error.description);
            //TODO: Error handling
        }
    }];
}

- (void)makePrivateRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    [[NCAPIController sharedInstance] makeRoomPrivate:room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self fetchRoomsWithCompletionBlock:nil];
        } else {
            NSLog(@"Error making private the room: %@", error.description);
            //TODO: Error handling
        }
    }];
}

- (void)setPasswordToRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    NSString *alertTitle = room.hasPassword ? @"Set new password:" : @"Set password:";
    UIAlertController *renameDialog =
    [UIAlertController alertControllerWithTitle:alertTitle
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    [renameDialog addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Password";
        textField.secureTextEntry = YES;
    }];
    
    NSString *actionTitle = room.hasPassword ? @"Change password" : @"OK";
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *password = [[renameDialog textFields][0] text];
        NSString *trimmedPassword = [password stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [[NCAPIController sharedInstance] setPassword:trimmedPassword toRoom:room.token withCompletionBlock:^(NSError *error) {
            if (!error) {
                [self fetchRoomsWithCompletionBlock:nil];
            } else {
                NSLog(@"Error setting room password: %@", error.description);
                //TODO: Error handling
            }
        }];
    }];
    [renameDialog addAction:confirmAction];
    
    if (room.hasPassword) {
        UIAlertAction *removePasswordAction = [UIAlertAction actionWithTitle:@"Remove password" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [[NCAPIController sharedInstance] setPassword:@"" toRoom:room.token withCompletionBlock:^(NSError *error) {
                if (!error) {
                    [self fetchRoomsWithCompletionBlock:nil];
                } else {
                    NSLog(@"Error changing room password: %@", error.description);
                    //TODO: Error handling
                }
            }];
        }];
        [renameDialog addAction:removePasswordAction];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [renameDialog addAction:cancelAction];
    
    [self presentViewController:renameDialog animated:YES completion:nil];
}

- (void)addRoomToFavoritesAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    [[NCAPIController sharedInstance] addRoomToFavorites:room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self fetchRoomsWithCompletionBlock:nil];
        } else {
            NSLog(@"Error adding room to favorites: %@", error.description);
            //TODO: Error handling
        }
    }];
}

- (void)removeRoomFromFavoritesAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    [[NCAPIController sharedInstance] removeRoomFromFavorites:room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self fetchRoomsWithCompletionBlock:nil];
        } else {
            NSLog(@"Error removing room from favorites: %@", error.description);
            //TODO: Error handling
        }
    }];
}

- (void)leaveRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:@"Leave conversation"
                                        message:@"Do you really want to leave this conversation?"
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Leave" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [_rooms removeObjectAtIndex:indexPath.row];
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        [[NCAPIController sharedInstance] removeSelfFromRoom:room.token withCompletionBlock:^(NSError *error) {
            if (!error) {
                [self fetchRoomsWithCompletionBlock:nil];
            } else {
                NSLog(@"Error leaving room: %@", error.description);
                //TODO: Error handling
            }
        }];
    }];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)deleteRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:@"Delete conversation"
                                        message:@"Do you really want to delete this conversation?"
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [_rooms removeObjectAtIndex:indexPath.row];
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        [[NCAPIController sharedInstance] deleteRoom:room.token withCompletionBlock:^(NSError *error) {
            if (!error) {
                [self fetchRoomsWithCompletionBlock:nil];
            } else {
                NSLog(@"Error deleting room: %@", error.description);
                //TODO: Error handling
            }
        }];
    }];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)presentChatForRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    [[NCRoomsManager sharedInstance] startChatInRoom:room];
}

#pragma mark - Utils

- (NSString *)getDateLabelStringForDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    if ([date isToday]) {
        [formatter setDateFormat:@"HH:mm"];
    } else if ([date isYesterday]) {
        return @"Yesterday";
    } else {
        [formatter setDateFormat:@"dd/MM/yy"];
    }
    return [formatter stringFromDate:date];
}

#pragma mark - Public Calls

- (void)showShareDialogForRoom:(NCRoom *)room withTitle:(NSString *)title
{
    NSInteger roomIndex = [_rooms indexOfObject:room];
    NSIndexPath *roomIndexPath = [NSIndexPath indexPathForRow:roomIndex inSection:0];
    
    UIAlertController *shareRoomDialog =
    [UIAlertController alertControllerWithTitle:title
                                        message:@"Do you want to share this conversation with others?"
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self shareLinkFromRoomAtIndexPath:roomIndexPath];
    }];
    [shareRoomDialog addAction:confirmAction];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Not now" style:UIAlertActionStyleCancel handler:nil];
    [shareRoomDialog addAction:cancelAction];
    
    [self presentViewController:shareRoomDialog animated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _rooms.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 80.0f;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

- (NSString *)tableView:(UITableView *)tableView titleForSwipeAccessoryButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    if (room.canModerate || room.isPublic) {
        NSString *moreButtonText = @"More";
        return moreButtonText;
    }
    
    return nil;
}

- (void)tableView:(UITableView *)tableView swipeAccessoryButtonPushedForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:room.displayName
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add/Remove room to/from favorites
    if ([[NCSettingsController sharedInstance] serverHasTalkCapability:kCapabilityFavorites]) {
        UIAlertAction *favoriteAction = [UIAlertAction actionWithTitle:(room.isFavorite) ? @"Remove from favorites" : @"Add to favorites"
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^void (UIAlertAction *action) {
                                                                   if (room.isFavorite) {
                                                                       [self removeRoomFromFavoritesAtIndexPath:indexPath];
                                                                   } else {
                                                                       [self addRoomToFavoritesAtIndexPath:indexPath];
                                                                   }
                                                               }];
        [favoriteAction setValue:[[UIImage imageNamed:@"favorite-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:favoriteAction];
    }
    // Share link of public calls even if you are not a moderator
    if (!room.canModerate && room.isPublic) {
        // Share Link
        UIAlertAction *shareLinkAction = [UIAlertAction actionWithTitle:@"Share link"
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^void (UIAlertAction *action) {
                                                                    [self shareLinkFromRoomAtIndexPath:indexPath];
                                                                }];
        [shareLinkAction setValue:[[UIImage imageNamed:@"public-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:shareLinkAction];
    // Moderator options
    } else {
        // Add participant
        UIAlertAction *addParticipantAction = [UIAlertAction actionWithTitle:@"Add participant"
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^void (UIAlertAction *action) {
                                                                         [self addParticipantInRoomAtIndexPath:indexPath];
                                                                     }];
        [addParticipantAction setValue:[[UIImage imageNamed:@"add-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:addParticipantAction];
        
        // Rename
        if (room.isNameEditable) {
            UIAlertAction *renameAction = [UIAlertAction actionWithTitle:@"Rename"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                     [self renameRoomAtIndexPath:indexPath];
                                                                 }];
            [renameAction setValue:[[UIImage imageNamed:@"rename-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [optionsActionSheet addAction:renameAction];
        }
        
        // Public/Private room options
        if (room.isPublic) {
            
            // Set Password
            UIAlertAction *passwordAction = [UIAlertAction actionWithTitle:(room.hasPassword) ? @"Change password" : @"Set password"
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^void (UIAlertAction *action) {
                                                                       [self setPasswordToRoomAtIndexPath:indexPath];
                                                                   }];
            [passwordAction setValue:[[UIImage imageNamed:@"no-password-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            if (room.hasPassword) {
                [passwordAction setValue:[[UIImage imageNamed:@"password-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            }
            [optionsActionSheet addAction:passwordAction];
            
            // Share Link
            UIAlertAction *shareLinkAction = [UIAlertAction actionWithTitle:@"Share link"
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^void (UIAlertAction *action) {
                                                                        [self shareLinkFromRoomAtIndexPath:indexPath];
                                                                    }];
            [shareLinkAction setValue:[[UIImage imageNamed:@"public-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [optionsActionSheet addAction:shareLinkAction];
            
            // Make call private
            UIAlertAction *makePrivateAction = [UIAlertAction actionWithTitle:@"Make conversation private"
                                                                        style:UIAlertActionStyleDefault
                                                                      handler:^void (UIAlertAction *action) {
                                                                          [self makePrivateRoomAtIndexPath:indexPath];
                                                                      }];
            [makePrivateAction setValue:[[UIImage imageNamed:@"group-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [optionsActionSheet addAction:makePrivateAction];
        } else {
            // Make call public
            UIAlertAction *makePublicAction = [UIAlertAction actionWithTitle:@"Make conversation public"
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^void (UIAlertAction *action) {
                                                                         [self makePublicRoomAtIndexPath:indexPath];
                                                                     }];
            [makePublicAction setValue:[[UIImage imageNamed:@"public-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [optionsActionSheet addAction:makePublicAction];
        }
        
        // Delete room
        if (room.isDeletable) {
            UIAlertAction *deleteCallAction = [UIAlertAction actionWithTitle:@"Delete conversation"
                                                                       style:UIAlertActionStyleDestructive
                                                                     handler:^void (UIAlertAction *action) {
                                                                         [self deleteRoomAtIndexPath:indexPath];
                                                                     }];
            [deleteCallAction setValue:[[UIImage imageNamed:@"delete-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [optionsActionSheet addAction:deleteCallAction];
        }
        
    }
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *deleteButtonText = @"Leave";
    return deleteButtonText;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self leaveRoomAtIndexPath:indexPath];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    RoomTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRoomCellIdentifier];
    if (!cell) {
        cell = [[RoomTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRoomCellIdentifier];
    }
    
    // Set room name
    cell.labelTitle.text = room.displayName;
    
    if ([[NCSettingsController sharedInstance]serverHasTalkCapability:kCapabilityLastRoomActivity]) {
        // Set last activity
        NCChatMessage *lastMessage = room.lastMessage;
        if (lastMessage) {
            cell.titleOnly = NO;
            cell.labelSubTitle.attributedText = room.lastMessageString;
        } else {
            cell.titleOnly = YES;
        }
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:room.lastActivity];
        cell.dateLabel.text = [self getDateLabelStringForDate:date];
    } else {
        // Set last ping
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:room.lastPing];
        cell.labelSubTitle.text = [date timeAgoSinceNow];
        if (room.lastPing == 0) {
            cell.labelSubTitle.text = @"Never joined";
        }
    }
    
    // Set unread messages
    if (room.unreadMessages > 0) {
        RoundedNumberView *unreadMessagesView = [[RoundedNumberView alloc] init];
        if ([[NCSettingsController sharedInstance]serverHasTalkCapability:kCapabilityMentionFlag]) {
            unreadMessagesView.important = room.unreadMention ? YES : NO;
        }
        unreadMessagesView.number = room.unreadMessages;
        unreadMessagesView.frame = CGRectMake(cell.unreadMessagesView.frame.size.width - unreadMessagesView.frame.size.width,
                                              unreadMessagesView.frame.origin.y,
                                              unreadMessagesView.frame.size.width, unreadMessagesView.frame.size.height);
        [cell.unreadMessagesView addSubview:unreadMessagesView];
    }
    
    // Set room image
    switch (room.type) {
        case kNCRoomTypeOneToOneCall:
        {
            // Create avatar for every OneToOne call
            [cell.roomImage setImageWithString:room.displayName color:nil circular:true];
            
            // Request user avatar to the server and set it if exist
            [cell.roomImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:room.name andSize:96]
                                  placeholderImage:nil success:nil failure:nil];
        }
            break;
            
        case kNCRoomTypeGroupCall:
            [cell.roomImage setImage:[UIImage imageNamed:@"group-bg"]];
            break;
            
        case kNCRoomTypePublicCall:
            [cell.roomImage setImage:(room.hasPassword) ? [UIImage imageNamed:@"public-password-bg"] : [UIImage imageNamed:@"public-bg"]];
            break;
            
        default:
            break;
    }
    
    // Set favorite image
    if (room.isFavorite) {
        [cell.favoriteImage setImage:[UIImage imageNamed:@"favorite-room"]];
    }
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([NCConnectionController sharedInstance].connectionState == kConnectionStateDisconnected) {
        [[NCUserInterfaceController sharedInstance] presentOfflineWarningAlert];
    } else {
        [self presentChatForRoomAtIndexPath:indexPath];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}


@end
