//
//  MenuViewController.m
//  Created by lukasz karluk on 12/12/11.
//

#import "MyAppViewController.h"
#import "ARSessionSetup.h"
#import "OFAppViewController.h"
#import "ofApp.h"

using namespace ofxARKit::core;

@interface MyAppViewController()
@property (nonatomic, strong) ARSession *session;
@end

@implementation MyAppViewController


- (void)loadView {
    [super loadView];

    SessionFormat format;
    format.enablePlaneTracking().enableLighting();
    self.session = generateNewSession(format);
    
    
    OFAppViewController *viewController;
    viewController = [[OFAppViewController alloc] initWithFrame:[[UIScreen mainScreen] bounds]
                                                                 app:new ofApp(self.session)];
    
    [self.navigationController setNavigationBarHidden:TRUE];
    [self.navigationController pushViewController:viewController animated:NO];
    self.navigationController.navigationBar.topItem.title = @"ofApp";
}


- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    BOOL bRotate = NO;
    bRotate = bRotate || (toInterfaceOrientation == UIInterfaceOrientationPortrait);
    bRotate = bRotate || (toInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown);
    return bRotate;
}

@end
