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

#import "HLPPreviewer.h"
#import "NavDataStore.h"
#import "ServerConfig+Preview.h"
#import "HLPGeoJSON+External.h"

#define TIMER_INTERVAL (1.0/64.0)
#define INITIAL_SPEED (2.0)
#define MAX_SPEED (INITIAL_SPEED*1.5*1.5*1.5*1.5)
#define MIN_SPEED (INITIAL_SPEED/1.5/1.5)
#define SPEED_FACTOR (1.5)


@interface TemporalLocationObject : HLPLocationObject
@end

@implementation TemporalLocationObject {
    HLPLocation *_location;
}

- (instancetype) initWithLocation:(HLPLocation*)location {
    self = [super init];
    _location = location;
    return self;
}

- (HLPLocation*) location{
    return _location;
}
@end

@implementation HLPPreviewEvent {
    HLPLocation *_location;
    NSArray *_linkPoisCache;
    HLPPreviewer *_previewer;
    BOOL _isSteppingBackward;
}

typedef NS_ENUM(NSUInteger, HLPPreviewHeadingType) {
    HLPPreviewHeadingTypeForward = 0,
    HLPPreviewHeadingTypeBackward,
    HLPPreviewHeadingTypeOther,
};

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:HLPPreviewEvent.class]) {
        HLPPreviewEvent* target = (HLPPreviewEvent*)object;
        if ([self.link isEqual:target.link] &&
            [self.target isEqual:target.target] &&
            [self.routeLink isEqual:target.routeLink]) {
            return YES;
        }
    }
    return NO;
}

- (id)copyWithZone:(NSZone*)zone
{
    HLPPreviewEvent *temp = [[[self class] allocWithZone:zone] initForPreviewer:_previewer
                                                                     withLink:_link
                                                                   Location:_location
                                                                Orientation:_orientation
                                                                    onRoute:_routeLink];
    [temp setDistanceMoved:_distanceMoved];
    [temp setPrev:_prev];
    return temp;
}

- (instancetype)initForPreviewer:(HLPPreviewer*)previewer withLink:(HLPLink *)link Location:(HLPLocation*)location Orientation:(double)orientation onRoute:(HLPLink*)routeLink
{
    self = [super init];
    _previewer = previewer;
    _link = link;
    _orientation = orientation;
    _routeLink = routeLink;
    [self setLocation:location];

    return self;
}

- (NSArray*) _linkPois
{
    if (!_linkPoisCache) {
        NSArray *temp = [NavDataStore sharedDataStore].linkPoiMap[_link._id];
        if (temp) {
            temp = [temp sortedArrayUsingComparator:^NSComparisonResult(HLPPOI *poi1, HLPPOI *poi2) {
                HLPLocation *l1 = [_link nearestLocationTo:poi1.location];
                HLPLocation *l2 = [_link nearestLocationTo:poi2.location];
                double diff = [l1 distanceTo:_link.sourceLocation] - [l2 distanceTo:_link.sourceLocation];
                
                if (self._sourceToTarget) {
                    return diff < 0 ? NSOrderedAscending : NSOrderedDescending;
                }
                else if (self._targetToSource) {
                    return diff > 0 ? NSOrderedAscending : NSOrderedDescending;
                }
                return NSOrderedSame;
            }];

            /*
            [temp enumerateObjectsUsingBlock:^(HLPPOI *poi, NSUInteger idx, BOOL * _Nonnull stop) {
                HLPLocation *l = [_link nearestLocationTo:poi.location];
                double dist = [l distanceTo:self._sourceToTarget?_link.sourceLocation:_link.targetLocation];
                NSLog(@"%@ %.2f", poi._id, dist);
            }];
             */
        }
        _linkPoisCache = temp;
    }
    return _linkPoisCache;
}

- (void)setLocation:(HLPLocation *)location
{
    _location = location;
    _linkPoisCache = nil; // clear cache

    if (_link == nil) {
        return;
    }
    if (self.target == nil) {
        return;
    }
    
    NavDataStore *nds = [NavDataStore sharedDataStore];
    
    NSArray *links = [self intersectionLinks];
    
    HLPLink *nextLink = nil;
    HLPLink *nextRouteLink = nil;
    double min = DBL_MAX;
    double min2 = DBL_MAX;
    BOOL isInitial = isnan(_orientation);
    if (isInitial) _orientation = 0;
    
    // find possible next link and possible next route link
    if ([self.target isKindOfClass:HLPNode.class]) {
        for(HLPLink *l in links) {
            double d = 0;
            if (l.sourceNode == self.target) {
                d = fabs([HLPLocation normalizeDegree:_orientation - l.initialBearingFromSource]);
            }
            else if (l.targetNode == self.target) {
                d = fabs([HLPLocation normalizeDegree:_orientation - l.initialBearingFromTarget]);
            }
            if (d < min) {
                min = d;
                nextLink = l;
            }
            
            // special for elevator
            if ([nds isElevatorNode:self.targetNode]) {
                if (l.linkType != LINK_TYPE_ELEVATOR) {
                    nextRouteLink = [nds findElevatorLink:l];
                }
            }
            else if (d < min2 && [nds isOnRoute:l._id]) {
                min2 = d;
                nextRouteLink = [nds routeLinkById:l._id];
            }
        }

        if (isInitial) _orientation = min;
        
        if (min < 20) {
            _link = nextLink;
            if (_link.sourceNode == self.target) {
                _orientation = _link.initialBearingFromSource;
            }
            else if (_link.targetNode == self.target) {
                _orientation = _link.initialBearingFromTarget;
            }
        } else {
            // if it is on elevator, face to the exit
            
            if ([nds isElevatorNode:self.targetNode]) {
                _orientation = [_link initialBearingFrom:self.targetNode];
            }            
        }
        // otherwise keep previous link
        
        _routeLink = nextRouteLink;
    }
}

- (BOOL) isOnRoute
{
    if (self.target == nil) {
        return NO;
    }
    NavDataStore *nds = [NavDataStore sharedDataStore];
    
    if ([nds isElevatorNode:self.targetNode]) {
        return [nds hasRoute] && [nds isOnRoute:self.targetNode._id];
    } else {
        return [nds hasRoute] && _link && _routeLink;
    }
}

- (BOOL) isGoingToBeOffRoute
{
    NavDataStore *nds = [NavDataStore sharedDataStore];
    
    return [nds hasRoute] && _link && _routeLink && ![_link._id isEqualToString:_routeLink._id];
}

- (BOOL)isGoingBackward
{
    NavDataStore *nds = [NavDataStore sharedDataStore];
    
    return [nds hasRoute] && _link && _routeLink && [_link._id isEqualToString:_routeLink._id] &&
    fabs(_orientation - _routeLink.initialBearingFromTarget) < 0.1;
}

- (BOOL)isArrived
{
    if (self.targetNode == nil) {
        return NO;
    }
    NavDataStore *nds = [NavDataStore sharedDataStore];
    return [nds isOnDestination:self.targetNode._id];
}

- (BOOL)isOnElevator
{
    return self.targetNode && [[NavDataStore sharedDataStore] isElevatorNode:self.targetNode];
}

- (BOOL)isInFrontOfElevator
{
    NavDataStore *nds = [NavDataStore sharedDataStore];
    if (_link.length < 5) {
        if ([nds isElevatorNode:_link.sourceNode]) {
            return [_link.targetNode isEqual:self.targetNode];
        }
        else if ([nds isElevatorNode:_link.targetNode]) {
            return [_link.sourceNode isEqual:self.targetNode];
        }
    }
    return NO;
}

- (void)setIsSteppingBackward:(BOOL)isSteppingBackward
{
    _isSteppingBackward = isSteppingBackward;
}

- (BOOL)isSteppingBackward
{
    return _isSteppingBackward;
}

- (BOOL)hasIntersectionName
{
    return [self intersectionName] != nil;
}

- (NSString*)intersectionName
{
    HLPNode *node = self.targetNode;
    if (!node) {
        return nil;
    }
    if (!self.link.streetName) {
        return nil;
    }
    NSArray<HLPLink*>* links = [self intersectionConnectionLinks];
    links = [links filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(HLPLink* link, NSDictionary<NSString *,id> * _Nullable bindings) {
        return link.streetName != nil && link.streetName.length > 0;
    }]];
    if (links.count == 0) {
        return nil;
    }
    NSString *name = links.firstObject.streetName;
    for(int i = 1; i < links.count; i++) {
        if (![name isEqualToString:links[i].streetName]) {
            return nil;
        }
    }
    return [NSString stringWithFormat:@"%@ with %@", self.link.streetName, name];
}

- (double)turnAngleToLink:(HLPLink*)link at:(HLPObject*)object
{
    if ([object isKindOfClass:HLPNode.class]) {
        return [self turnAngleToLink:link atNode:(HLPNode*)object];
    }
    return [HLPLocation normalizeDegree:self.orientation + 180];
}

- (double)turnAngleToLink:(HLPLink*)link atNode:(HLPNode*)node
{
    double linkDir = NAN;
    if (link.sourceNode == node) {
        linkDir = link.initialBearingFromSource;
    }
    else if (link.targetNode == node) {
        linkDir = link.initialBearingFromTarget;
    }
    else {
        NSLog(@"%@ is not node of the link %@", node._id, link._id);
    }
    return [HLPLocation normalizeDegree:linkDir - self.orientation];
}

- (HLPLocation*)location
{
    double floor = 0;
    if (self.targetNode) {
        floor = self.targetNode.height;
    } else if (_link) {
        floor = _link.sourceHeight;
    }
    return [[HLPLocation alloc] initWithLat:_location.lat Lng:_location.lng Accuracy:0 Floor:floor Speed:0 Orientation:_orientation OrientationAccuracy:0];
}

- (HLPPreviewHeadingType) headingType
{
    if (isnan(_location.orientation)) {
        return HLPPreviewHeadingTypeOther;
    }
    
    double f = [_link bearingAtLocation:_location];
    double b = [HLPLocation normalizeDegree:180-f];
    
    if (fabs([HLPLocation normalizeDegree:_location.orientation - f]) < 5) {
        return HLPPreviewHeadingTypeForward;
    }

    if (fabs([HLPLocation normalizeDegree:_location.orientation - b]) < 5) {
        return HLPPreviewHeadingTypeForward;
    }

    return HLPPreviewHeadingTypeOther;
}

- (NSArray<HLPLink*>*)intersectionLinks
{
    NavDataStore *nds = [NavDataStore sharedDataStore];
    NSArray *links = nds.nodeLinksMap[self.target._id];
    HLPNode *node = self.targetNode;
    
    return [links filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(HLPLink *link, NSDictionary<NSString *,id> * _Nullable bindings) {
        if (link.direction == DIRECTION_TYPE_SOURCE_TO_TARGET) {
            return (link.sourceNode == node);
        }
        if (link.direction == DIRECTION_TYPE_TARGET_TO_SOURCE) {
            return (link.targetNode == node);
        }
        return link.isLeaf == NO || link.length >= 3;
    }]];
}

- (NSArray<HLPLink*>*)intersectionConnectionLinks
{
    HLPNode *node = self.targetNode;
    if (!node) {
        return nil;
    }
    NSArray<HLPLink*>* links = self.intersectionLinks;
    if (!links) {
        return nil;
    }
    return [links filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(HLPLink* link, NSDictionary<NSString *,id> * _Nullable bindings) {
        double heading = [self turnAngleToLink:link atNode:node];
        return 20 < fabs(heading) && fabs(heading) < 180-20;
    }]];
}

- (BOOL) _sourceToTarget {
    return fabs(_orientation - _link.initialBearingFromSource) < 0.01;
}

- (BOOL) _targetToSource {
    return fabs(_orientation - _link.initialBearingFromTarget) < 0.01;
}

- (HLPLocationObject*) stepTarget
{
    if (_link == nil) {
        return nil;
    }
    
    HLPLocationObject *next = nil;
    if (self.target == nil) {
        if (self._sourceToTarget) {
            next = _link.targetNode;
        } else if (self._targetToSource) {
            next = _link.sourceNode;
        }
    } else {
        NSArray<HLPLocationObject*> *stepTargets = self._linkPois;
        if (stepTargets == nil) stepTargets = @[];
        
        if (self._sourceToTarget) {
            stepTargets = [@[_link.sourceNode] arrayByAddingObjectsFromArray:stepTargets];
            stepTargets = [stepTargets arrayByAddingObject:_link.targetNode];
        } else if (self._targetToSource) {
            stepTargets = [@[_link.targetNode] arrayByAddingObjectsFromArray:stepTargets];
            stepTargets = [stepTargets arrayByAddingObject:_link.sourceNode];
        }
        
        unsigned long j = 0;
        for(unsigned long i = 0; i < stepTargets.count; i++) {
            HLPLocationObject *lo = stepTargets[i];
            if (![lo isKindOfClass:HLPLocationObject.class]) {
                continue;
            }
            if ([[_link nearestLocationTo:lo.location] distanceTo:_location] < 0.5) {
                j = MIN((i+1), stepTargets.count-1);
            }
        }
        
        next = stepTargets[j];
        
        /* test
        if ([_location distanceTo:stepTargets[j].location] > 5) {
            HLPLocation *loc = [_location offsetLocationByDistance:5 Bearing:[_location bearingTo:stepTargets[j].location]];
            next = [[TemporalLocationObject alloc] initWithLocation:loc];
        } else {
            next = stepTargets[j];
        }
         */
        
    }
    return next;
}

- (HLPLocation*)stepTargetLocation
{
    return [_link nearestLocationTo:self.stepTarget.location];
}

- (double)distanceToStepTarget
{
    HLPLocation *loc = self.stepTargetLocation;
    if (loc) {
        return [loc distanceTo:_location];
    }
    return NAN;
}

- (void) setPrev:(HLPPreviewEvent *)prev
{
    _prev = prev;
}

- (HLPPreviewEvent *)next
{
    HLPPreviewEvent *temp = self;
    HLPLocationObject *prevTarget = nil;

    double distance = 0;
    while(true) {
        HLPPreviewEvent *prev = temp;
        temp = [temp copy];
        [temp setPrev:prev];
        
        if (temp.stepTarget == prevTarget && [prev.link._id isEqualToString:prev.prev.link._id]) {
            temp = prev;
            break;
        }
        
        if ((prevTarget = temp.stepTarget)) {
            distance += [temp distanceToStepTarget];
            [temp setLocation:temp.stepTargetLocation];
            
            if (self.isOnRoute && (temp.targetPOIs || temp.isGoingBackward)) {
                break;
            }
            if (self.isOnRoute && temp.targetIntersection && temp.isGoingToBeOffRoute) {
                break;
            }
            if (self.isOnRoute && temp.isInFrontOfElevator) {
                break;
            }
            if (!self.isOnRoute && (temp.targetPOIs || temp.targetIntersection)) {
                break;
            }
            if (temp.hasIntersectionName) {
                break;
            }
        } else {
            break;
        }
    }
    [temp setDistanceMoved:distance];

    return temp;
}

- (HLPPreviewEvent *)right
{
    if (self.rightLink) {
        HLPPreviewEvent *temp = [self copy];
        double tempori = temp.orientation;
        [temp turnToLink:self.rightLink];
        temp->_turnedAngle = [HLPLocation normalizeDegree:temp.orientation - tempori];
        if (temp->_turnedAngle < 0) {
            temp->_turnedAngle += 360;
        }
        return temp;
    }
    return nil;
}

- (HLPPreviewEvent *)left
{
    if (self.leftLink) {
        HLPPreviewEvent *temp = [self copy];
        double tempori = temp.orientation;
        [temp turnToLink:self.leftLink];
        temp->_turnedAngle = [HLPLocation normalizeDegree:temp.orientation - tempori];
        if (temp->_turnedAngle > 0) {
            temp->_turnedAngle -= 360;
        }
        return temp;
    }
    return nil;
}

- (HLPPreviewEvent *)upFloor
{
    if (self.upFloorLink) {
        HLPPreviewEvent *temp = [self copy];
        [temp turnToLink:self.upFloorLink];
        temp->_turnedAngle = NAN;
        return temp;
    }
    return nil;
}

- (HLPPreviewEvent *)downFloor
{
    if (self.downFloorLink) {
        HLPPreviewEvent *temp = [self copy];
        [temp turnToLink:self.downFloorLink];
        temp->_turnedAngle = NAN;
        return temp;
    }
    return nil;
}

- (HLPPreviewEvent *)nextAction
{
    HLPPreviewEvent *next = self.next;
    double d = next.distanceMoved;
    while(YES) {
        if (!next.isOnRoute || next.isGoingToBeOffRoute || next.isArrived ||
            [[NavDataStore sharedDataStore] isElevatorNode: next.targetNode]) {
            break;
        }
        next = next.next;
        d += next.distanceMoved;
    }
    [next setDistanceMoved:d];
    return next;
}


- (void)turnToLink:(HLPLink*)link
{
    if (_link == link) {
        _orientation = [HLPLocation normalizeDegree:_orientation+180];
    } else {
        _link = link;
        _orientation = (_link.sourceNode == self.target)?_link.initialBearingFromSource:_link.initialBearingFromTarget;
    }
    [self setLocation:_location];
}

- (HLPLocationObject*) target
{
    if (_link == nil) {
        return nil;
    }
    if (_location == nil) {
        return nil;
    }
    if ([_link.sourceNode.location distanceTo:_location] < 0.5) {
        return _link.sourceNode;
    }
    if ([_link.targetNode.location distanceTo:_location] < 0.5) {
        return _link.targetNode;
    }
    NSArray *pois = self._linkPois;
    if (pois) {
        for(HLPLocationObject *lo in pois) {
            if ([[_link nearestLocationTo:lo.location] distanceTo:_location] < 0.01) {
                return lo;
            }
        }
    }
    
    return nil;
}

- (HLPNode*)  targetNode
{
    if ([self.target isKindOfClass:HLPNode.class]) {
        return (HLPNode*)self.target;
    }
    return nil;
}

- (HLPNode *)targetIntersection
{
    if (self.targetNode == nil) {
        return nil;
    }
    
    if ([[NavDataStore sharedDataStore] isElevatorNode:self.targetNode]) {
        return self.targetNode;
    }
    
    NSArray *links = [self intersectionLinks];
    if (links.count > 2) {
        return self.targetNode;
    }
    return nil;
}

- (HLPNode *)targetCorner
{
    if (self.targetNode == nil) {
        return nil;
    }
    
    if ([[NavDataStore sharedDataStore] isElevatorNode:self.targetNode]) {
        return self.targetNode;
    }
    
    NSArray<HLPLink*> *links = [self intersectionLinks];
    if (links.count == 2) {
        double diff = [HLPLocation normalizeDegree:links[0].initialBearingFromSource - links[1].initialBearingFromSource];
        if (20 <= fabs(diff) && fabs(diff) <= 160) {
            return self.targetNode;
        }
    }
    return nil;
}

- (BOOL) isEffective:(HLPLocationObject*)obj
{
    NSString *name = nil;
    if ([obj isKindOfClass:HLPEntrance.class] && ((HLPEntrance*)obj).node.isLeaf) {
        if ([[NavDataStore sharedDataStore] isOnDestination:((HLPEntrance*)obj).node._id] ||
            [[NavDataStore sharedDataStore] isOnStart:((HLPEntrance*)obj).node._id] ||
            ((HLPEntrance*)obj).facility.isExternalPOI ||
            (!_previewer.isAutoProceed && ![[NSUserDefaults standardUserDefaults] boolForKey:@"ignore_facility_for_jump2"]) ||
            (_previewer.isAutoProceed && ![[NSUserDefaults standardUserDefaults] boolForKey:@"ignore_facility_for_walk2"])) {
            name = ((HLPEntrance*)obj).facility.name;
        }
    }
    if ([obj isKindOfClass:HLPPOI.class]) {
        HLPPOI *poi = (HLPPOI*)obj;
        if(poi.poiCategory == HLPPOICategoryInfo && ([poi isOnFront:self.location] || [poi isOnSide:self.location])) {
            name = poi.name;
        }
        if(poi.poiCategory == HLPPOICategoryDoor && ([poi isOnFront:self.location])) {            
            name = NSLocalizedStringFromTable(poi.flags.flagAuto?@"AutoDoorPOIString1": @"DoorPOIString1", @"BlindView", @"");
        }
        if(poi.poiCategory == HLPPOICategoryElevator && ([poi isOnFront:self.location])) {
            name = poi.elevatorButtons.description;
        }
    }
    return name && name.length > 0;
}

- (NSArray<HLPLocationObject *> *)targetPOIs
{
    if (self._linkPois == nil) {
        return nil;
    }
    
    NSMutableArray *temp = [@[] mutableCopy];
    for(HLPLocationObject *obj in self._linkPois) {
        if ([[_link nearestLocationTo:obj.location] distanceTo:_location] < 0.5) {
            if ([self isEffective:obj]) {
                [temp addObject:obj];
            }
        }
    }
    if ([temp count] > 0) {
        return temp;
    }
    return nil;
}

- (NSArray<HLPEntrance *> *)targetFacilityPOIs
{
    if (self._linkPois == nil) {
        return nil;
    }
    
    NSMutableArray *temp = [@[] mutableCopy];
    for(HLPLocationObject *obj in self._linkPois) {
        if ([obj isKindOfClass:HLPEntrance.class]) {
            if ([[_link nearestLocationTo:obj.location] distanceTo:_location] < 0.5) {
                if ([self isEffective:obj]) {
                    [temp addObject:obj];
                }
            }
        }
    }
    if ([temp count] > 0) {
        return temp;
    }
    return nil;
}


- (HLPPOI*) cornerPOI
{
    for(HLPLocationObject *obj in self._linkPois) {
        if (![obj isKindOfClass:HLPPOI.class]) {
            continue;
        }
        HLPPOI *poi = (HLPPOI*)obj;
        if (poi.poiCategory == HLPPOICategoryCornerEnd || poi.poiCategory == HLPPOICategoryCornerLandmark) {
            if ([[_link nearestLocationTo:obj.location] distanceTo:_location] < 3 &&
                [poi isOnFront:self.location]) {
                return poi;
            }
        }
    }
    return nil;
}

- (HLPPOI*) elevatorPOI
{
    NavDataStore *nds = [NavDataStore sharedDataStore];
    NSArray *links = nds.nodeLinksMap[self.targetNode._id];
    for(HLPLink* link in links) {
        if (link.linkType == LINK_TYPE_ELEVATOR) {
            NSArray *pois = nds.linkPoiMap[link._id];
            for(HLPPOI *poi in pois) {
                if (poi.poiCategory == HLPPOICategoryElevator) {
                    return poi;
                }
            }
        }
    }
    return nil;
}

- (HLPPOI*) elevatorEquipmentsPOI
{
    NavDataStore *nds = [NavDataStore sharedDataStore];
    NSArray *links = nds.nodeLinksMap[self.targetNode._id];
    for(HLPLink* link in links) {
        if (link.linkType == LINK_TYPE_ELEVATOR) {
            NSArray *pois = nds.linkPoiMap[link._id];
            for(HLPPOI *poi in pois) {
                if (poi.poiCategory == HLPPOICategoryElevatorEquipments) {
                    return poi;
                }
            }
        }
    }
    return nil;
}

- (HLPLink*) _nextLink:(BOOL)clockwise
{
    if (self.target == nil) {
        return nil;
    }
    if (self.targetNode == nil) {
        return _link;
    }

    NavDataStore *nds = [NavDataStore sharedDataStore];
    NSArray<HLPLink*> *links = [self intersectionLinks];

    if (clockwise) {
        NSInteger index = -1;
        for(NSInteger i = 0; i < links.count; i++) {
            HLPLink *link = links[i];
            double lo = [link initialBearingFrom:(HLPNode*)self.target];
            if (lo <= _orientation) {
                index = i;
            }
        }
        return links[(index + 1) % links.count];
    } else {
        NSInteger index = links.count;
        for(NSInteger i = links.count-1; i >= 0; i--) {
            HLPLink *link = links[i];
            double lo = [link initialBearingFrom:(HLPNode*)self.target];
            if (lo >= _orientation) {
                index = i;
            }
        }
        return links[(index + links.count - 1) % links.count];
    }
}

- (HLPLink*) _floorLink:(BOOL)up
{
    HLPNode *node = self.targetNode;
    NavDataStore *nds = [NavDataStore sharedDataStore];
    
    HLPLink *minLink = nil;
    double target = round(node.height)+(up?1:-1);
    double floor = up?INT_MAX:INT_MIN;
    for(HLPLink *l in nds.nodeLinksMap[node._id]) {
        if (l.linkType == LINK_TYPE_ELEVATOR) {
            if (l.sourceNode == node) {
                if ((up && target < l.targetNode.height && l.targetNode.height < floor) ||
                    (!up && target > l.targetNode.height && l.targetNode.height > floor)) {
                    minLink = l;
                    floor = l.targetNode.height;
                    node = l.targetNode;
                }
            }
            else if (l.targetNode == node) {
                if ((up && target < l.sourceNode.height && l.sourceNode.height < floor) ||
                    (!up && target > l.sourceNode.height && l.sourceNode.height > floor)) {
                    minLink = l;
                    floor = l.sourceNode.height;
                    node = l.sourceNode;
                }
            }
        }
    }
    if (node == nil || node == self.targetNode) {
        return nil;
    }
    for(HLPLink *l in nds.nodeLinksMap[node._id]) {
        if (l.linkType != LINK_TYPE_ELEVATOR) {
            return l;
        }
    }
    return nil;
}

- (HLPLink*) leftLink
{
    return [self _nextLink:NO];
}

- (HLPLink*) rightLink
{
    return [self _nextLink:YES];
}

- (HLPLink*) downFloorLink
{
    NavDataStore *nds = [NavDataStore sharedDataStore];
    if ([nds isElevatorNode:self.targetNode]) {
        return [self _floorLink:NO];
    }
    return nil;
}

- (HLPLink*) upFloorLink
{
    NavDataStore *nds = [NavDataStore sharedDataStore];
    if ([nds isElevatorNode:self.targetNode]) {
        return [self _floorLink:YES];
    }
    return nil;
}

- (void)setDistanceMoved:(double)distanceMoved
{
    _distanceMoved = distanceMoved;
}

- (NSString*)description
{
    NSMutableString *temp = [@"\n---------------\n" mutableCopy];

    [temp appendFormat:@"Link  : %@\n", _link._id];
    [temp appendFormat:@"Loc   : %@\n", _location];
    [temp appendFormat:@"Ori   : %f\n", _orientation];
    [temp appendFormat:@"Right : %@\n", self.rightLink._id];
    [temp appendFormat:@"Left  : %@\n", self.leftLink._id];
    [temp appendFormat:@"Target: %@\n", self.target._id];
    [temp appendFormat:@"Next  : %@\n", self.stepTarget._id];
    [temp appendFormat:@"POIS  : %ld\n", self.targetPOIs.count];
    [temp appendFormat:@"Dist  : %f\n", _distanceMoved];
    
    return temp;
}
@end


@implementation HLPPreviewer {
    NavDataStore *nds;
    HLPPreviewEvent *current;
    NSMutableArray<HLPPreviewEvent*> *history;
    NSArray *route;
    
    NSTimer *autoTimer;
    double stepSpeed;
    double stepCounter;
    double remainingDistanceToNextStep;
    double remainingDistanceToNextAction;
    HLPLocation *currentLocation;
}

- (instancetype) init
{
    self = [super init];
    history = [@[] mutableCopy];
    stepSpeed = INITIAL_SPEED;
    return self;
}

- (HLPPreviewEvent*) event
{
    return current;
}

- (void)startAt:(HLPLocation *)loc
{
    nds = [NavDataStore sharedDataStore];
    route = nds.route;
    
    //find nearest link
    double min = DBL_MAX;
    HLPLink *minLink = nil;
    HLPLink *routeLink = nil;
    double ori = NAN;
    
    // with route
    if ([nds hasRoute]) {
        HLPLink *first = [nds firstRouteLink:3];
        // route HLPLink is different instance from linksMap so need to get by link id
        routeLink = first;
        minLink = nds.linksMap[first._id];
        loc = first.sourceNode.location;
        ori = first.initialBearingFromSource;
        
    // without route
    } else {
        if (nds.to._id != nil) {
            [_delegate routeNotFound];
            return;
        }
        
        for(NSObject *key in nds.linksMap) {
            HLPLink *link = nds.linksMap[key];
            if (link.isLeaf) {
                continue;
            }
            if (link.sourceNode.height != link.targetNode.height ||
                link.sourceNode.height != loc.floor) {
                continue;
            }
            double d = [[link nearestLocationTo:loc] distanceTo:loc];
            if (d < min) {
                min = d;
                minLink = link;
            }
        }
        if (minLink) {
            loc = [minLink nearestLocationTo:loc];
            ori = minLink.initialBearingFromTarget;
        }
    }

    if (minLink) {
        current = [[HLPPreviewEvent alloc] initForPreviewer:self withLink:minLink Location:loc Orientation:ori onRoute:routeLink];
    } else {
        //NSLog(@"no link found");
        //[_delegate errorWithMessage:@"closest link is not found"];
    }
    
    _isActive = YES;
    [self firePreviewStarted];
}

- (void)stop
{
    _isActive = NO;
    current = nil;
    [history removeAllObjects];
    [self _autoStepStop];
    [self fireUserLocation:current.location];
    [_delegate previewStopped:current];
}



- (void)firePreviewUpdated
{
    if (current.isArrived) {
        [self _autoStepStop];
    }
    if ((current.isOnRoute && current.isGoingToBeOffRoute) ||
        (current.targetNode && [[NavDataStore sharedDataStore] isElevatorNode:current.targetNode] && current.isGoingBackward)) {
        [self _autoStepPause];
    }

    remainingDistanceToNextStep = current.next.distanceMoved;
    remainingDistanceToNextAction = current.nextAction.distanceMoved;
    [self fireRemainingDistance:remainingDistanceToNextAction];    
    [self fireUserLocation:current.location];
    [_delegate previewUpdated:current];
}

- (void)firePreviewStarted
{
    remainingDistanceToNextStep = current.next.distanceMoved;
    remainingDistanceToNextAction = current.nextAction.distanceMoved;
    [self fireUserLocation:current.location];
    [_delegate previewStarted:current];
}

- (void)fireUserMoved:(double)distance
{
    if (_isAutoProceed == NO) {
        [_delegate userMoved:distance];
    }
}

- (void)fireUserLocation:(HLPLocation*)location
{
    HLPLocation *loc = [[HLPLocation alloc] init];
    [loc update:location];
    [loc updateOrientation:current.orientation withAccuracy:0];
    currentLocation = loc;
    [_delegate userLocation:loc];
}

- (void)fireRemainingDistance:(double)distance
{
    if (_isAutoProceed) {
        [_delegate remainingDistance:distance];
    }
}

#pragma mark - PreviewTraverseDelegate

- (void)gotoBegin
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    [self _autoStepStop];
    if (history.count > 0) {
        current = history[0];
    }
    [history removeAllObjects];
    current.isSteppingBackward = YES;
    [self firePreviewStarted];
}

- (void)gotoEnd
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    
    if (![[NavDataStore sharedDataStore] hasRoute]) {
        [self fireUserMoved:0];
        return;
    }
    [self _autoStepStop];
    double distance = 0;
    int count = 0;
    while(true) {
        double d = [self _stepForward];
        distance += d;
        if (d == 0) {
            if ([[NavDataStore sharedDataStore] isOnDestination:current.targetNode._id]) {
                break;
            }
            [current turnToLink:current.routeLink];
        }
        count++;
        if (count > 10000) {
            break;
        }
    }
    [self fireUserMoved:distance];
    [self firePreviewUpdated];
}

- (void)stepForward
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    double distance = [self _stepForward];
    if (!isnan(distance)) {
        [self _autoStepStop];        
    }
    [self fireUserMoved:distance];
    [self firePreviewUpdated];
}

- (double)_stepForward
{
    // special elevator behavior for with route
    if (current.isOnRoute && current.isGoingBackward && current.isOnElevator) {
        if (current.upFloor.isOnRoute) {
            HLPPreviewEvent *temp = current.upFloor;
            while(temp.isOnRoute && temp.isGoingToBeOffRoute) {
                temp = temp.upFloor;
            }
            current = temp;
        } else {
            HLPPreviewEvent *temp = current.downFloor;
            while(temp.isOnRoute && temp.isGoingToBeOffRoute) {
                temp = temp.downFloor;
            }
            current = temp;
        }
        [self _autoStepResume];
        return NAN;
    }
    
    HLPPreviewEvent *next = [current next];
    if ([[NavDataStore sharedDataStore] hasRoute] &&
        [[NSUserDefaults standardUserDefaults] boolForKey:@"prevent_offroute"] && !next.isOnRoute) {
        return 0;
    }
    if (next.distanceMoved > 0.1) {
        [history addObject:current];
        current = next;
    }
    return next.distanceMoved;
}

- (void)stepBackward
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    [self _autoStepStop];
    if (history.count > 0) {
        double distance = current.distanceMoved;
        current = [history lastObject];
        current.isSteppingBackward = YES;
        [history removeLastObject];
        
        [self fireUserMoved:-distance];
        [self firePreviewUpdated];
    } else {
        [self fireUserMoved:0];
    }
}

- (void)jumpForward
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    [self _autoStepStop];
    double distance = 0;
    while(true) {
        double d = [self _stepForward];
        distance += d;
        if (current.targetIntersection || current.targetCorner || current.isArrived) {
            break;
        }
    }
    [self fireUserMoved:distance];
    [self firePreviewUpdated];
}

- (void)jumpBackward
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    [self _autoStepStop];
    if (history.count > 0) {
        double distance = 0;
        while (history.count > 0) {
            distance += current.distanceMoved;
            current = [history lastObject];
            [history removeLastObject];
            if (current.targetIntersection || current.targetCorner) {
                break;
            }
        }
        [self fireUserMoved:-distance];
        [self firePreviewUpdated];
    } else {
        [self fireUserMoved:0];
    }
}

- (void)_faceTo:(HLPPreviewEvent*)temp
{
    if (temp) {
        BOOL preventOffroute = [[NavDataStore sharedDataStore] hasRoute] &&
                               [[NSUserDefaults standardUserDefaults] boolForKey:@"prevent_offroute"];
        if (preventOffroute && temp.isGoingToBeOffRoute) {
            [self fireUserMoved:0];
            [self firePreviewUpdated];
        } else if (preventOffroute && temp.isGoingBackward) {
            [self fireUserMoved:0];
        } else {
            [temp setPrev:current];
            current = temp;
            [self firePreviewUpdated];
        }
    } else {
        [self fireUserMoved:0];
    }
}

- (void)faceRight
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    [self _autoStepResume];
    
    if ([[NavDataStore sharedDataStore] isElevatorNode:current.targetNode]) {
        if (![[NavDataStore sharedDataStore] hasRoute]) {
            [self _faceTo:current.upFloor];
        } else {
            [_delegate userMoved:0];
        }
    } else {
        [self _faceTo:current.right];
    }
}

- (void)faceLeft
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    [self _autoStepResume];
    
    if ([[NavDataStore sharedDataStore] isElevatorNode:current.targetNode]) {
        if (![[NavDataStore sharedDataStore] hasRoute]) {
            [self _faceTo:current.downFloor];
        } else {
            [_delegate userMoved:0];
        }
    } else {
        [self _faceTo:current.left];
    }
}

- (void)autoStepForwardUp
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    if (_isAutoProceed) {
        stepSpeed = MIN(stepSpeed * SPEED_FACTOR, MAX_SPEED);
        return;
    }
    [self _autoStepStart];
}

- (void)_autoStepStart
{
    if (!autoTimer) {
        stepCounter = 1;
        autoTimer = [NSTimer scheduledTimerWithTimeInterval:TIMER_INTERVAL target:self selector:@selector(autoStep:) userInfo:nil repeats:YES];
    }
    
    _isAutoProceed = YES;
    _isWaitingAction = NO;
    
    remainingDistanceToNextStep = current.next.distanceMoved;
    remainingDistanceToNextAction = current.nextAction.distanceMoved;
}

- (void)_autoStepPause
{
    if (_isAutoProceed) {
        _isAutoProceed = NO;
        _isWaitingAction = YES;
    } else {
        _isAutoProceed = NO;
        _isWaitingAction = NO;
    }
}

- (void)_autoStepResume
{
    if (_isWaitingAction) {
        _isWaitingAction = NO;
        if (!_isAutoProceed) {
            [self _autoStepStart];
        }
    }
}

- (void)_autoStepStop
{
    _isAutoProceed = NO;
    _isWaitingAction = NO;
}

- (void)autoStepForwardDown
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    if (_isAutoProceed) {
        stepSpeed = MAX(stepSpeed / SPEED_FACTOR, MIN_SPEED);
    }
}

- (void)autoStepForwardStop
{
    NSLog(@"%@,%f", NSStringFromSelector(_cmd), NSDate.date.timeIntervalSince1970);
    
    [self _autoStepStop];
}

- (void)autoStepForwardSpeed:(double)speed Active:(BOOL)active
{
    NSLog(@"%@,%f,%d,%f", NSStringFromSelector(_cmd), speed, active, NSDate.date.timeIntervalSince1970);
    
    
}

- (void)autoStep:(NSTimer*)timer
{
    if (_isWaitingAction) {
        return;
    }
    if (_isAutoProceed == NO) {
        [autoTimer invalidate];
        autoTimer = nil;
    }
    
    stepCounter += TIMER_INTERVAL * stepSpeed;
    if (stepCounter >= 1.0) {
        double step_length = [[NSUserDefaults standardUserDefaults] doubleForKey:@"preview_step_length"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (_isAutoProceed) {
                currentLocation = [currentLocation offsetLocationByDistance:step_length Bearing:currentLocation.orientation];
                [self fireUserLocation:currentLocation];
            }
        });
        stepCounter -= 1.0;
        
        if (_isAutoProceed) {            
            remainingDistanceToNextStep -= step_length;
            remainingDistanceToNextAction -= step_length;
            [self fireRemainingDistance:remainingDistanceToNextAction];
            if (remainingDistanceToNextStep < step_length) {
                [_delegate userMoved:NAN];
                [self _stepForward];
                [self firePreviewUpdated];
            }
        }
    }
}

@end
