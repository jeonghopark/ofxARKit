//
//  MyAppDelegate.m
//  Created by lukasz karluk on 12/12/11.
//

#import "MyAppDelegate.h"
#import "MyAppViewController.h"

@implementation MyAppDelegate

@synthesize navigationController;

// UIScene을 사용하지 않도록 명시적으로 설정
- (UISceneConfiguration *)application:(UIApplication *)application 
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession 
                              options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0)) {
    return nil;  // Scene을 사용하지 않음
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    NSLog(@"🏁 didFinishLaunchingWithOptions 시작 (super 호출 전)");
    
    [super applicationDidFinishLaunching:application];
    
    NSLog(@"🏁 super 호출 완료");
    NSLog(@"   Window exists: %@", self.window ? @"YES" : @"NO");
    if (self.window) {
        NSLog(@"   Window rootViewController: %@", self.window.rootViewController);
    }
    
    // Request camera authorization early
    [self requestCameraAuthorization];
    
    /**
     *
     *  Below is where you insert your own UIViewController and take control of the App.
     *  In this example im creating a UINavigationController and adding it as my RootViewController to the window. (this is essential)
     *  UINavigationController is handy for managing the navigation between multiple view controllers, more info here,
     *  http://developer.apple.com/library/ios/#documentation/uikit/reference/UINavigationController_Class/Reference/Reference.html
     *
     *  I then push oFAppViewController onto the UINavigationController stack.
     *  oFAppViewController is a custom view controller with a 3 button menu.
     *
     **/
    
    MyAppViewController *myVC = [[MyAppViewController alloc] init];
    self.navigationController = [[UINavigationController alloc] initWithRootViewController:myVC];
    
    NSLog(@"🔨 NavigationController created with root view controller");
    NSLog(@"   View controllers in stack: %lu", (unsigned long)self.navigationController.viewControllers.count);
    
    [self.window setRootViewController:self.navigationController];
    
    NSLog(@"📦 NavigationController set as root");
    
    // Make window visible
    [self.window makeKeyAndVisible];
    
    NSLog(@"🪟 Window made visible");
    NSLog(@"   Window frame: %@", NSStringFromCGRect(self.window.frame));
    NSLog(@"   Window root VC: %@", self.window.rootViewController);
    
    // Force view loading and appearance
    [myVC view];
    NSLog(@"🔧 Explicitly triggered view loading");
    
    // Force layout
    [self.window layoutIfNeeded];
    
    // Manually trigger view appearance if needed
    dispatch_async(dispatch_get_main_queue(), ^{
        [myVC beginAppearanceTransition:YES animated:NO];
        [myVC endAppearanceTransition];
        NSLog(@"🔧 Manually triggered appearance transition");
    });
    
    //--- style the UINavigationController
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor systemBackgroundColor];
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    } else {
        self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    }
    self.navigationController.navigationBar.topItem.title = @"Home";
    
    return YES;
}

- (void)requestCameraAuthorization {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    
    if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted) {
                NSLog(@"✅ Camera access granted");
            } else {
                NSLog(@"❌ Camera access denied by user");
            }
        }];
    } else if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted) {
        NSLog(@"⚠️ Camera access is denied or restricted");
    } else if (status == AVAuthorizationStatusAuthorized) {
        NSLog(@"✅ Camera access already authorized");
    }
}

- (void) dealloc {
    self.navigationController = nil;
}

@end
