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

#import "POIViewController.h"
#import "NavDataStore.h"
#import "HLPGeoJSON+External.h"

@interface POIViewController ()

@end

@implementation POIViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    if (_pois) {
        HLPFacility *external = [self findExternal];
        if (external) {
            NSURL *url = external.externalPOIWebpage;
            if (url) {
                self.navigationItem.title = [NSString stringWithFormat:@"%@ webpage", external.externalSourceTitle];
                [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
                return;
            }
        }
        
        NSString *content = [self extractContent];
        [self.webView loadHTMLString:content baseURL:nil];
    }
}

- (HLPFacility*) findExternal
{
    for(HLPEntrance *poi in _pois) {
        if (poi.facility.isExternalPOI) {
            return poi.facility;
        }
    }
    return nil;
}

- (NSString*) extractContent
{
    NSMutableString *str = [@"<html><body>" mutableCopy];
    for(HLPEntrance *poi in _pois) {
        [str appendFormat:@"<h1>%@</h1>", [poi name]];
        if (poi.facility.longDescription) {
            [str appendFormat:@"<div>%@</div>", poi.facility.longDescription];
        }
    }
    [str appendString:@"</body></html>"];
    return str;
}

- (BOOL)isContentAvailable
{
    if ([self findExternal]) {
        return YES;
    }
    for(HLPEntrance *poi in _pois) {
        if (poi.facility.longDescription && poi.facility.longDescription.length > 0) {
            return YES;
        }
    }
    return NO;    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
