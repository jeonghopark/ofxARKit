//
//  CustomAppViewController.m
//  Created by lukasz karluk on 8/02/12.
//

#import "OFAppViewController.h"
#include "ofxiOSExtras.h"
#include "ofAppiOSWindow.h"



@implementation OFAppViewController
- (void) viewDidLoad {
    [super viewDidLoad];
    
    NSLog(@"🎬 OFAppViewController viewDidLoad");
    NSLog(@"   View: %@", self.view);
    NSLog(@"   View frame: %@", NSStringFromCGRect(self.view.frame));
    NSLog(@"   View backgroundColor: %@", self.view.backgroundColor);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    NSLog(@"🔜 OFAppViewController viewWillAppear");
    NSLog(@"   Navigation controller: %@", self.navigationController);
    NSLog(@"   View controllers in stack: %lu", (unsigned long)self.navigationController.viewControllers.count);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    NSLog(@"✨ OFAppViewController viewDidAppear");
    NSLog(@"   View is in window: %@", self.view.window ? @"YES" : @"NO");
    NSLog(@"   View superview: %@", self.view.superview);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    NSLog(@"👋 OFAppViewController viewWillDisappear");
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    NSLog(@"💨 OFAppViewController viewDidDisappear");
}


- (id) initWithFrame:(CGRect)frame app:(ofxiOSApp *)app {
    
    ofxiOSGetOFWindow()->setOrientation( OF_ORIENTATION_DEFAULT );   //-- default portait orientation.    
    
    return self = [super initWithFrame:frame app:app];
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return NO;
}

@end
