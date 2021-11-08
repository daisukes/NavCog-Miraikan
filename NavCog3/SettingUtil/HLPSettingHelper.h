/*******************************************************************************
 * Copyright (c) 2014, 2015  IBM Corporation, Carnegie Mellon University and others
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

#import <Foundation/Foundation.h>
#import "HLPSetting.h"
#import "HLPSettingViewCell.h"
#import <UIKit/UIKit.h>

@class HLPSettingHelper;

@protocol HLPSettingHelperDelegate <NSObject>
-(void)actionPerformed:(HLPSetting*)setting;
@end

@interface HLPSettingHelper : NSObject <UITableViewDataSource, UITableViewDelegate, HLPSettingViewCellDelegate>

@property NSMutableArray *settings;
@property NSMutableDictionary *groups;
@property (weak) id<HLPSettingHelperDelegate> delegate;


- (HLPSetting*)addSettingWithType:(NavCogSettingType)type
                            Label:(NSString*)label
                             Name:(NSString*)name
                     DefaultValue:(NSObject*)defaultValue
                           Accept:(NSObject*(^)(NSObject*))handler;

- (HLPSetting*)addSettingWithType:(NavCogSettingType)type
                            Label:(NSString*)label
                             Name:(NSString*)name
                            Group:(NSString*)group
                     DefaultValue:(NSObject*)defaultValue
                           Accept:(NSObject*(^)(NSObject*))handler;

- (HLPSetting*) addSettingWithType:(NavCogSettingType)type
                             Label:(NSString*)label
                              Name:(NSString*)name
                      DefaultValue:(NSObject*)defaultValue
                               Min:(double)min
                               Max:(double)max
                          Interval:(double)interval;

- (HLPSetting*) addSectionTitle:(NSString*)title;
- (HLPSetting*) addActionTitle:(NSString*)title Name:(NSString*)name;
- (void) removeAllSetting;

- (NSInteger) numberOfSections;
- (NSInteger) numberOfRowsInSection:(NSInteger)section;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
- (NSString*) titleForSection: (NSInteger) row;
- (void) setVisible:(BOOL) visible Section: (NSInteger) section;

- (void) exportSetting:(NSMutableDictionary*)dic;


@end

