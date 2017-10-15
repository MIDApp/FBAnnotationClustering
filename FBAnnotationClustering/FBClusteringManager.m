//
//  FBClusterManager.m
//  AnnotationClustering
//
//  Created by Filip Bec on 05/01/14.
//  Copyright (c) 2014 Infinum Ltd. All rights reserved.
//

#import "FBClusteringManager.h"
#import "FBQuadTree.h"

static NSString * const kFBClusteringManagerLockName = @"co.infinum.clusteringLock";

#pragma mark - Utility functions

NSInteger FBZoomScaleToZoomLevel(double scale)
{
    return (NSInteger)floor(scale);
}

CGFloat FBCellSizeForZoomScale(double zoomScale)
{
    NSInteger zoomLevel = FBZoomScaleToZoomLevel(zoomScale);
    
    switch (zoomLevel) {
        case 13:
        case 14:
        case 15:
            return 64;
        case 16:
        case 17:
        case 18:
            return 32;
        case 19:
            return 16;
            
        default:
            return zoomLevel > 19 ? 16 : 88;
    }
}

#pragma mark - FBClusteringManager

@interface FBClusteringManager ()

@property (nonatomic, strong) FBQuadTree *tree;
@property (nonatomic, strong) NSRecursiveLock *lock;
@property (nonatomic, strong) NSMutableSet *types;

@end


@implementation FBClusteringManager

- (id)init
{
    return [self initWithAnnotations:nil];
}

- (id)initWithAnnotations:(NSArray *)annotations
{
    self = [super init];
    if (self) {
        _lock = [NSRecursiveLock new];
        _types = [NSMutableSet setWithObject:[FBAnnotationCluster class]];
        [self addAnnotations:annotations];
    }
    return self;
}

- (void)setAnnotations:(NSArray *)annotations
{
    self.tree = nil;
    [self addAnnotations:annotations];
}

- (void)addAnnotations:(NSArray *)annotations
{
    if (!self.tree) {
        self.tree = [[FBQuadTree alloc] init];
    }

    [self.lock lock];
    for (id<MGLAnnotation> annotation in annotations) {
        
        if (![self.types containsObject:[annotation class]]) {
            [self.types addObject:[annotation class]];
        }
        
        [self.tree insertAnnotation:annotation];
    }
    [self.lock unlock];
}

- (void)removeAnnotations:(NSArray *)annotations
{
    if (!self.tree) {
        return;
    }

    [self.lock lock];
    for (id<MGLAnnotation> annotation in annotations) {
        [self.tree removeAnnotation:annotation];
    }
    [self.lock unlock];
}

- (NSArray *)clusteredAnnotationsWithinCoordinateBounds:(MGLCoordinateBounds)rect withZoomScale:(double)zoomScale
{
    return [self clusteredAnnotationsWithinCoordinateBounds:rect
                                              withZoomScale:zoomScale
                                                 withFilter:nil];
}

- (NSArray *)clusteredAnnotationsWithinCoordinateBounds:(MGLCoordinateBounds)rect
                                          withZoomScale:(double)zoomScale
                                             withFilter:(BOOL (^)(id<MGLAnnotation>)) filter
{
    double cellSize = FBCellSizeForZoomScale(zoomScale);
    if ([self.delegate respondsToSelector:@selector(cellSizeFactorForCoordinator:)]) {
        cellSize *= [self.delegate cellSizeFactorForCoordinator:self];
    }
    
    FBBoundingBox mapBox = FBBoundingBoxForCoordinateBounds(rect);
    CLLocationDegrees delta = mapBox.xf - mapBox.x0;
    delta *= cellSize/375.;
    
    NSMutableArray *clusteredAnnotations = [[NSMutableArray alloc] init];
    
    [self.lock lock];
    FBBoundingBox currentMapBox  = FBBoundingBoxMake(0., 0., 0., 0.);
    
    currentMapBox.y0 = mapBox.y0;
    currentMapBox.yf = currentMapBox.y0 + delta;
    
    do
    {
        currentMapBox.x0 = mapBox.x0;
        currentMapBox.xf = currentMapBox.x0 + delta;
        do
        {
            __block double totalLatitude = 0;
            __block double totalLongitude = 0;
            
            NSMutableArray *annotations = [[NSMutableArray alloc] init];

            [self.tree enumerateAnnotationsInBox:currentMapBox usingBlock:^(id<MGLAnnotation> obj) {
                
                if(!filter || (filter(obj) == TRUE))
                {
                    totalLatitude += [obj coordinate].latitude;
                    totalLongitude += [obj coordinate].longitude;
                    [annotations addObject:obj];
                }
            }];
            
            NSInteger count = [annotations count];
            static const NSInteger minAnnotationsCountToCluster = 2;
            if (count < minAnnotationsCountToCluster) {
                [clusteredAnnotations addObjectsFromArray:annotations];
            }
            
            if (count >= minAnnotationsCountToCluster) {
                CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(totalLatitude/count, totalLongitude/count);
                FBAnnotationCluster *cluster = [[FBAnnotationCluster alloc] init];
                cluster.coordinate = coordinate;
                cluster.annotations = annotations;
                [clusteredAnnotations addObject:cluster];
            }
        
            currentMapBox.x0 += delta;
            currentMapBox.xf += delta;
        }
        while (currentMapBox.x0 <= mapBox.xf);
        
        currentMapBox.y0 += delta;
        currentMapBox.yf += delta;
    }
    while (currentMapBox.y0 <= mapBox.yf);
    
    [self.lock unlock];
    
    return [NSArray arrayWithArray:clusteredAnnotations];
}

- (NSArray *)allAnnotations
{
    NSMutableArray *annotations = [[NSMutableArray alloc] init];
    
    [self.lock lock];
    [self.tree enumerateAnnotationsUsingBlock:^(id<MGLAnnotation> obj) {
        [annotations addObject:obj];
    }];
    [self.lock unlock];
    
    return annotations;
}

- (void)displayAnnotations:(NSArray *)annotations onMapView:(MGLMapView *)mapView
{
    NSOperationQueue *queue = [NSOperationQueue currentQueue];
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        NSArray *oldAnnotations = mapView.annotations;
        if (queue)
        {
            [queue addOperationWithBlock:^{
                
                [self displayAnnotations:annotations
                    replacingAnnotations:oldAnnotations
                               onMapView:mapView];
            }];
        }
        else
        {
            [self displayAnnotations:annotations
                replacingAnnotations:oldAnnotations
                           onMapView:mapView];
        }
    }];
}

- (void)displayAnnotations:(NSArray *)annotations
      replacingAnnotations:(NSArray *)oldAnnotations
                 onMapView:(MGLMapView *)mapView
{
    if (!annotations.count && !oldAnnotations.count)
    {
        return;
    }
    // Only consider Annotations in mapView that are managed by BFClusteringManager
    NSArray *filteredAnnotations = [oldAnnotations filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        
        return [self.types containsObject:[evaluatedObject class]];
    }]];
    
    NSMutableSet *before = [NSMutableSet setWithArray:filteredAnnotations];
    
    NSSet *after = [NSSet setWithArray:annotations];
    
    NSMutableSet *toKeep = [NSMutableSet setWithSet:before];
    [toKeep intersectSet:after];
    
    NSMutableSet *toAdd = [NSMutableSet setWithSet:after];
    [toAdd minusSet:toKeep];
    
    NSMutableSet *toRemove = [NSMutableSet setWithSet:before];
    [toRemove minusSet:after];
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [mapView addAnnotations:[toAdd allObjects]];
        [mapView removeAnnotations:[toRemove allObjects]];
    }];
}

@end
