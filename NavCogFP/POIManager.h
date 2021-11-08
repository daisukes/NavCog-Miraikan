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

#import <Foundation/Foundation.h>
#import "HLPGeoJSON.h"

@class POIManager;
@protocol POIManagerDelegate
-(void) didStartLoading;
-(void) manager:(POIManager*)manager didPOIsLoaded:(NSArray<HLPObject*>*)pois;
-(void) manager:(POIManager*)manager requestInfo:(NSString *)type forPOI:(NSDictionary*)poi at:(HLPLocation*)loc withOptions:(NSDictionary*)options;
@end

@interface POIManager : NSObject
@property id<POIManagerDelegate> delegate;
+(instancetype)sharedManager;
-(void)initCenter:(HLPLocation*)loc;
-(void)loadPOIs;
-(void)addPOI:(NSDictionary*)poi at:(HLPLocation*)location withOptions:(NSDictionary*)options;
-(void)removePOI:(HLPGeoJSONFeature*)poi;
-(HLPNode*)nodeForFaciligy:(HLPFacility*)facility;
-(HLPNode*)nodeByID:(NSString*)nodeid;
@end
