//
//  FBViewController.m
//  AnnotationClustering
//
//  Created by Filip Bec on 06/04/14.
//  Copyright (c) 2014 Infinum Ltd. All rights reserved.
//

#import "FBViewController.h"
#import "FBAnnotation.h"

#define kNUMBER_OF_LOCATIONS 50
#define kFIRST_LOCATIONS_TO_REMOVE 50

@interface FBViewController ()

@property (weak, nonatomic) IBOutlet MGLMapView *mapView;
@property (weak, nonatomic) IBOutlet UILabel *numberOfAnnotationsLabel;

@property (nonatomic, assign) NSUInteger numberOfLocations;
@property (nonatomic, strong) FBClusteringManager *clusteringManager;

@end

@implementation FBViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.

    NSMutableArray *array = [self randomLocationsWithCount:kNUMBER_OF_LOCATIONS];
    self.numberOfLocations = kNUMBER_OF_LOCATIONS;
    [self updateLabelText];
    
    // Create clustering manager
    self.clusteringManager = [[FBClusteringManager alloc] initWithAnnotations:array];
    self.clusteringManager.delegate = self;
    
    self.mapView.centerCoordinate = CLLocationCoordinate2DMake(0, 0);
    [self mapView:self.mapView regionDidChangeAnimated:NO];

//    NSMutableArray *annotationsToRemove = [[NSMutableArray alloc] init];
//    for (int i=0; i<kFIRST_LOCATIONS_TO_REMOVE; i++) {
//        [annotationsToRemove addObject:array[i]];
//    }
//    [self.clusteringManager removeAnnotations:annotationsToRemove];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - MGLMapViewDelegate

- (void)mapView:(MGLMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    double zoom = mapView.zoomLevel;
    MGLCoordinateBounds mapBounds = mapView.visibleCoordinateBounds;
    [[NSOperationQueue new] addOperationWithBlock:^{
        NSArray *annotations = [self.clusteringManager clusteredAnnotationsWithinCoordinateBounds:mapBounds withZoomScale:zoom];
        
        [self.clusteringManager displayAnnotations:annotations onMapView:mapView];
    }];
}

- (MGLAnnotationImage *)mapView:(MGLMapView *)mapView imageForAnnotation:(id<MGLAnnotation>)annotation
{
    MGLAnnotationImage *imageView;
    
    // This is how you can check if annotation is a cluster
    if ([annotation isKindOfClass:[FBAnnotationCluster class]])
    {
        FBAnnotationCluster *cluster = (FBAnnotationCluster *)annotation;
        cluster.title = [NSString stringWithFormat:@"%lu", (unsigned long)cluster.annotations.count];
        
        static NSString *const ClusterReuseID = @"ClusterReuseID";
        
        imageView = [mapView dequeueReusableAnnotationImageWithIdentifier:ClusterReuseID];
        
        if (!imageView)
        {
            imageView = [MGLAnnotationImage annotationImageWithImage:[UIImage imageNamed:@"cluster"] reuseIdentifier:ClusterReuseID];
            
        }
    }
    else
    {
        static NSString *const UnclusteredReuseID = @"UnclusteredReuseID";
        
        imageView = [mapView dequeueReusableAnnotationImageWithIdentifier:UnclusteredReuseID];
        
        if (!imageView)
        {
            imageView = [MGLAnnotationImage annotationImageWithImage:[UIImage imageNamed:@"unclustered"] reuseIdentifier:UnclusteredReuseID];
            imageView.enabled = NO;
            
        }
    }
    
    return imageView;
}

- (BOOL)mapView:(MGLMapView *)mapView annotationCanShowCallout:(id<MGLAnnotation>)annotation
{
    if ([annotation isKindOfClass:[FBAnnotationCluster class]])
        return YES;
    
    return NO;
}

#pragma mark - FBClusterManager delegate - optional

- (CGFloat)cellSizeFactorForCoordinator:(FBClusteringManager *)coordinator
{
    return 1.5;
}

#pragma mark - Add annotations button action handler

- (IBAction)addNewAnnotations:(id)sender
{
    NSMutableArray *array = [self randomLocationsWithCount:kNUMBER_OF_LOCATIONS];
    [self.clusteringManager addAnnotations:array];
    
    self.numberOfLocations += kNUMBER_OF_LOCATIONS;
    [self updateLabelText];
    
    // Update annotations on the map
    [self mapView:self.mapView regionDidChangeAnimated:NO];
}

#pragma mark - Utility

- (NSMutableArray *)randomLocationsWithCount:(NSUInteger)count
{
    srand48(time(NULL));
    
    NSMutableArray *array = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        FBAnnotation *a = [[FBAnnotation alloc] init];
        a.coordinate = CLLocationCoordinate2DMake(midRand() * 90., midRand() * 180.);
        
        [array addObject:a];
    }
    return array;
}

double midRand()
{
    return (drand48() - 0.5) * 2.;
}

- (void)updateLabelText
{
    self.numberOfAnnotationsLabel.text = [NSString stringWithFormat:@"Sum of all annotations: %lu", (unsigned long)self.numberOfLocations];
}

@end
