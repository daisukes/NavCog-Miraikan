/*******************************************************************************
 * Copyright (c) 2014, 2016  IBM Corporation, Carnegie Mellon University and others
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *******************************************************************************/


#import "WelcomViewController.h"
#import "ServerConfig+FingerPrint.h"
#import "AuthManager.h"
#import "LocationEvent.h"
#import "Logging.h"
#import "NavDataStore.h"

@interface WelcomViewController ()

@end

@implementation WelcomViewController {
    BOOL first;
    int agreementCount;
    int retryCount;
    BOOL networkError;
    UIViewController *vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
 
    agreementCount = 0;
    first = YES;
    
    [self updateView];
}

- (void)viewDidAppear:(BOOL)animated
{
    // TODO set serverlist address
    if (first) {
        first = NO;
        [self checkConfig];
    }
    self.navigationItem.hidesBackButton = YES;
}

- (void)updateView
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (networkError) {
            self.statusLabel.text = NSLocalizedString(@"checkNetworkConnection",@"");
        } else {
            self.statusLabel.text = @"";
        }
        self.retryButton.hidden = !networkError;
    });
}

- (void)didNetworkError
{
    networkError = YES;
    [self updateView];
}

- (IBAction)retry:(id)sender {
    networkError = NO;
    retryCount = 0;
    agreementCount = 0;
    [self updateView];
    [self checkConfig];
}

- (void) checkConfig
{
    if (self.presentedViewController) {
        //NSLog(@"Presenting: %@", self.presentedViewController);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1f*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self checkConfig];
        });
        return;
    }
    
    if (![[AuthManager sharedManager] isDeveloperAuthorized]) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"developer_mode"];
    }
    /*
    if ([[AuthManager sharedManager] isDeveloperAuthorized]) {
        [self performSegueWithIdentifier:@"show_mode_selection" sender:self];
        return;
    }
     */
    
    if (retryCount > 3) {
        [self didNetworkError];
        return;
    }
    retryCount++;
    
    ServerConfig *config = [ServerConfig sharedConfig];

    if (!config.selected) {
        if (config.serverList) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self performSegueWithIdentifier:@"show_server_selection" sender:self];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = NSLocalizedString(@"CheckServerList", @"");
            });
            [[ServerConfig sharedConfig] requestServerList:^(ServerList *config) {
                [self checkConfig];
                if (config) { retryCount = 0; }
            }];
        }

        return;
    }
    
    
    if (config.selected) {
        if (config.agreementConfig) {
            BOOL agreed = [config.agreementConfig[@"agreed"] boolValue];
            if (agreed) {
                // noop
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self performSegueWithIdentifier:@"show_agreement" sender:self];
                });
                return;
            }
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = NSLocalizedString(@"CheckAgreement", @"");
            });
            NSString *identifier = [[NavDataStore sharedDataStore] userID];
            [[ServerConfig sharedConfig] checkAgreementForIdentifier:identifier withCompletion:^(NSDictionary* config) {
                [self checkConfig];
                if (config) { retryCount = 0; }
            }];
            return;
        }
        
        if (config.selectedServerConfig) {
            NSArray *files = [config checkDownloadFiles];
            if ([files count] > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self performSegueWithIdentifier:@"show_download" sender:self];
                });
            } else {
                NSArray *files = config.downloadConfig[@"map_files"];
                NSFileManager *fm = [NSFileManager defaultManager];

                NSError *error;
                NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                for(NSString *path in files) {
                    NSString *toPath = [path lastPathComponent];
                    toPath = [docPath stringByAppendingPathComponent:toPath];
                    [fm removeItemAtPath:toPath error:nil];
                    [fm copyItemAtPath:path toPath:toPath error:&error];
                    
                    NSString *filename = [toPath lastPathComponent];
                    [[NSUserDefaults standardUserDefaults] setObject:filename forKey:@"bleloc_map_data"];
                }
                
                // copy preset files
                NSString *presetsDir = [docPath stringByAppendingPathComponent:@"presets"];
                [fm createDirectoryAtPath:presetsDir withIntermediateDirectories:YES attributes:nil error:nil];
                
                [config.downloadConfig enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                    if ([key hasPrefix:@"preset_for_"]) {
                        NSString *name = [NSString stringWithFormat:@"%@.plist", [key substringFromIndex: 11]];
                        NSString *path = [presetsDir stringByAppendingPathComponent:name];
                        [fm removeItemAtPath:path error:nil];
                        [fm copyItemAtPath:obj toPath:path error:nil];
                    }
                }];
                
                [[NSNotificationCenter defaultCenter] postNotificationName:SERVER_CONFIG_CHANGED_NOTIFICATION
                                                                    object:self
                                                                  userInfo:config.selectedServerConfig];

                //[Logging stopLog];
                //[Logging startLog];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString *hostname = config.selected.hostname;
                    [[NSUserDefaults standardUserDefaults] setObject:hostname forKey:@"selected_hokoukukan_server"];

                    if (![[ServerConfig sharedConfig] isFingerPrintingAvailable]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.statusLabel.text = NSLocalizedString(@"CheckServerConfig", @"");
                        });
                        config.selected = nil;
                        [self checkConfig];
                        return;
                    }

                    @try {
                        vc = [[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateViewControllerWithIdentifier:@"blind_ui_navigation"];
                        NSLog(@"%@", vc);
                        [self presentViewController:vc animated:YES completion:nil];
                    } @catch (NSException *ex){
                        NSLog(@"error(%@)",ex);
                    }
                });
            }
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = NSLocalizedString(@"CheckServerConfig", @"");
            });
            [[ServerConfig sharedConfig] requestServerConfig:^(NSDictionary *config) {
                [self checkConfig];
                if (config) { retryCount = 0; }
            }];
            return;
        }
    }
}

- (IBAction)returnActionForSegue:(UIStoryboardSegue *)segue
{
    [self checkConfig];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}


@end
