//
//  MenuViewController.m
//

#import "MyAppViewController.h"

#import "OFAppViewController.h"
#import "ofApp.h"
using namespace ofxARKit::core;
@interface MyAppViewController()
@property (nonatomic, strong) ARSession *session;
@end

@implementation MyAppViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLog(@"🎬 MyAppViewController init 호출됨");
    }
    return self;
}

- (void)loadView {
    NSLog(@"👁️ MyAppViewController loadView 호출됨");
    
    // Create a simple view
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    view.backgroundColor = [UIColor systemBackgroundColor];
    self.view = view;
    
    NSLog(@"👁️ View created: %@", self.view);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSLog(@"🔜 MyAppViewController viewWillAppear 호출됨");
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSLog(@"✨ MyAppViewController viewDidAppear 호출됨");
    
    // 카메라 권한 확인 및 AR 세션 초기화
    [self checkCameraAuthorizationAndSetup];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"🚀 MyAppViewController viewDidLoad 시작");
    NSLog(@"========================================");
    NSLog(@"");
}

- (void)checkCameraAuthorizationAndSetup {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    
    if (status == AVAuthorizationStatusAuthorized) {
        NSLog(@"✅ 카메라 권한 있음 - AR 세션 초기화");
        [self setupARSession];
    } else if (status == AVAuthorizationStatusNotDetermined) {
        NSLog(@"⚠️ 카메라 권한 요청 중...");
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    NSLog(@"✅ 카메라 권한 승인됨");
                    [self setupARSession];
                } else {
                    NSLog(@"❌ 카메라 권한 거부됨");
                    [self showCameraPermissionAlert];
                }
            });
        }];
    } else {
        NSLog(@"❌ 카메라 권한 없음");
        [self showCameraPermissionAlert];
    }
}

- (void)showCameraPermissionAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"카메라 권한 필요"
                                                                   message:@"AR 기능을 사용하려면 카메라 권한이 필요합니다."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"설정으로 이동" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction * action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]
                                           options:@{}
                                 completionHandler:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setupARSession {
    NSLog(@"🔧 setupARSession 시작");
    
    // ARKit 지원 여부 확인
    if (![ARWorldTrackingConfiguration isSupported]) {
        NSLog(@"❌ 이 기기는 ARWorldTracking을 지원하지 않습니다");
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AR 지원 안됨"
                                                                       message:@"이 기기는 AR 기능을 지원하지 않습니다."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSLog(@"✅ ARKit 지원 확인됨");
    
    // SessionFormat 설정 및 세션 생성
    SessionFormat format;
    format.enableLighting();
    
    self.session = generateNewSession(format);
    
    if(!self.session) {
        NSLog(@"❌ ARSession 생성 실패!");
        return;
    }
    
    NSLog(@"✅ ARSession 생성 및 시작 완료");
    
    // OFAppViewController 생성 및 표시
    OFAppViewController *viewController = [[OFAppViewController alloc] initWithFrame:[[UIScreen mainScreen] bounds]
                                                                                  app:new ofApp(self.session)];
    
    NSLog(@"✅ OFAppViewController 생성 완료");
    NSLog(@"   OFAppViewController: %@", viewController);
    NSLog(@"   View: %@", viewController.view);
    
    // Navigation push 대신 직접 전환
    if (self.navigationController) {
        NSLog(@"✅ Replacing root view controller with OFAppViewController");
        
        // Get the window
        UIWindow *window = self.view.window;
        if (!window) {
            window = [UIApplication sharedApplication].keyWindow;
        }
        
        NSLog(@"   Window: %@", window);
        NSLog(@"   Window: %@", window);
        
        // Replace root view controller directly (no animation)
        window.rootViewController = viewController;
        [window makeKeyAndVisible];
        
        NSLog(@"✅ 뷰 컨트롤러 전환 완료");
    } else {
        NSLog(@"❌ NavigationController 없음!");
    }
    
    NSLog(@"✅ 모든 초기화 완료");
}


- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    BOOL bRotate = NO;
    bRotate = bRotate || (toInterfaceOrientation == UIInterfaceOrientationPortrait);
    bRotate = bRotate || (toInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown);
    bRotate = bRotate || (toInterfaceOrientation == UIInterfaceOrientationLandscapeLeft);
    bRotate = bRotate || (toInterfaceOrientation == UIInterfaceOrientationLandscapeRight);
    return bRotate;
}

@end
