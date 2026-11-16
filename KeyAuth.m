#import <UIKit/UIKit.h>

// Sử dụng GitHub API trỏ thẳng tới file "key" trong repo bogiadatindo-dot/key để đồng bộ 0 giây (không bị cache)
#define GITHUB_API_URL @"https://api.github.com/repos/bogiadatindo-dot/key/contents/key"

#define SAVED_KEY_PREF @"SavedUserLicenseKey"
#define FIRST_LOGIN_ALERT @"HasShownWelcomeAlert"
#define IS_VERIFIED_BEFORE @"HasVerifiedKeyBefore"

static NSTimer *expiryTimer = nil;

@interface KeyManager : NSObject
+ (void)checkLicense;
+ (void)scheduleAutoKickAtDate:(NSDate *)expiryDate currentServerDate:(NSDate *)serverDate expiryString:(NSString *)expiryStr;
+ (void)forceLogoutAndExitWithReason:(NSString *)reason;
+ (void)showKeyPromptWithMessage:(NSString *)message prefillKey:(NSString *)prefill;
+ (void)showInfoAlertWithTitle:(NSString *)title message:(NSString *)message;
@end

@implementation KeyManager

+ (UIWindow *)getActiveWindow {
    UIWindow *foundWindow = nil;
    NSArray *windows = [[UIApplication sharedApplication] windows];
    for (UIWindow *window in windows) {
        if (window.isKeyWindow) {
            foundWindow = window;
            break;
        }
    }
    return foundWindow ?: windows.firstObject;
}

+ (NSDate *)getServerDateFromResponse:(NSURLResponse *)response {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSString *dateString = httpResponse.allHeaderFields[@"Date"];
        if (dateString) {
            NSDateFormatter *rfcFormatter = [[NSDateFormatter alloc] init];
            rfcFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            rfcFormatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss z";
            NSDate *serverDate = [rfcFormatter dateFromString:dateString];
            if (serverDate) return serverDate;
        }
    }
    return [NSDate date];
}

// Hẹn giờ tự động đá văng app ngay tại giây phút key hết hạn
+ (void)scheduleAutoKickAtDate:(NSDate *)expiryDate currentServerDate:(NSDate *)serverDate expiryString:(NSString *)expiryStr {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (expiryTimer) {
            [expiryTimer invalidate];
            expiryTimer = nil;
        }
        
        NSTimeInterval remainingSeconds = [expiryDate timeIntervalSinceDate:serverDate];
        
        if (remainingSeconds <= 0) {
            NSString *msg = [NSString stringWithFormat:@"Key đã hết hạn lúc %@. Ứng dụng sẽ thoát để nhập lại Key!", expiryStr];
            [self forceLogoutAndExitWithReason:msg];
            return;
        }
        
        expiryTimer = [NSTimer scheduledTimerWithTimeInterval:remainingSeconds repeats:NO block:^(NSTimer * _Nonnull timer) {
            NSString *msg = [NSString stringWithFormat:@"Key của bạn vừa hết hạn (%@). Ứng dụng sẽ tự động thoát!", expiryStr];
            [self forceLogoutAndExitWithReason:msg];
        }];
    });
}

// Xóa key cũ, hiện cảnh báo và buộc thoát app
+ (void)forceLogoutAndExitWithReason:(NSString *)reason {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SAVED_KEY_PREF];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:FIRST_LOGIN_ALERT];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:IS_VERIFIED_BEFORE];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self getActiveWindow];
        UIViewController *rootVC = window.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        
        if (rootVC) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Hết Thời Gian Sử Dụng"
                                                                           message:reason
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"Thoát App Ngay" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                exit(0);
            }];
            
            [alert addAction:exitAction];
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            exit(0);
        });
    });
}

+ (void)checkLicense {
    NSString *savedKey = [[NSUserDefaults standardUserDefaults] stringForKey:SAVED_KEY_PREF];
    BOOL wasVerifiedBefore = [[NSUserDefaults standardUserDefaults] boolForKey:IS_VERIFIED_BEFORE];
    
    if (!savedKey || savedKey.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showKeyPromptWithMessage:@"Vui lòng nhập Key kích hoạt để tiếp tục." prefillKey:nil];
        });
        return;
    }

    NSString *urlString = [NSString stringWithFormat:@"%@?t=%f", GITHUB_API_URL, [[NSDate date] timeIntervalSince1970]];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                                       timeoutInterval:15.0];
    [request setValue:@"no-cache, no-store, must-revalidate" forHTTPHeaderField:@"Cache-Control"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Pragma"];
    [request setValue:@"application/vnd.github.v3.raw" forHTTPHeaderField:@"Accept"];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showKeyPromptWithMessage:@"Lỗi kết nối mạng. Không thể kiểm tra Key!" prefillKey:savedKey];
            });
            return;
        }

        NSDate *currentDate = [self getServerDateFromResponse:response];
        
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"Asia/Ho_Chi_Minh"]];

        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        
        BOOL isKeyFound = NO;
        BOOL isExpired = NO;
        NSString *expiryDisplay = @"Vĩnh viễn";
        NSDate *validExpiryDate = nil;

        for (NSString *line in lines) {
            NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmedLine.length == 0) continue;

            NSArray *parts = [trimmedLine componentsSeparatedByString:@"|"];
            NSString *serverKey = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

            if ([serverKey isEqualToString:savedKey]) {
                isKeyFound = YES;
                
                if (parts.count > 1) {
                    NSString *expiryStr = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    
                    if (![expiryStr.uppercaseString isEqualToString:@"LIFETIME"]) {
                        validExpiryDate = [dateFormatter dateFromString:expiryStr];
                        expiryDisplay = expiryStr;
                        
                        if (validExpiryDate && [currentDate compare:validExpiryDate] == NSOrderedDescending) {
                            isExpired = YES;
                        }
                    }
                }
                break;
            }
        }

        if (!isKeyFound) {
            if (wasVerifiedBefore) {
                [self forceLogoutAndExitWithReason:@"Key của bạn đã bị thu hồi hoặc xóa khỏi hệ thống. Ứng dụng sẽ thoát!"];
            } else {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:SAVED_KEY_PREF];
                [[NSUserDefaults standardUserDefaults] synchronize];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showKeyPromptWithMessage:@"Key không tồn tại hoặc đang đồng bộ. Vui lòng kiểm tra lại và bấm Xác nhận!" prefillKey:savedKey];
                });
            }
        } else if (isExpired) {
            NSString *msg = [NSString stringWithFormat:@"Key đã hết hạn lúc %@. Ứng dụng sẽ thoát để nhập Key mới!", expiryDisplay];
            [self forceLogoutAndExitWithReason:msg];
        } else {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:IS_VERIFIED_BEFORE];
            [[NSUserDefaults standardUserDefaults] synchronize];

            if (validExpiryDate) {
                [self scheduleAutoKickAtDate:validExpiryDate currentServerDate:currentDate expiryString:expiryDisplay];
            }
            
            BOOL hasShown = [[NSUserDefaults standardUserDefaults] boolForKey:FIRST_LOGIN_ALERT];
            if (!hasShown) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:FIRST_LOGIN_ALERT];
                [[NSUserDefaults standardUserDefaults] synchronize];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString *welcomeMsg = [NSString stringWithFormat:@"Key: %@\nHạn dùng: %@", savedKey, expiryDisplay];
                    [self showInfoAlertWithTitle:@"Kích Hoạt Thành Công" message:welcomeMsg];
                });
            }
        }
    }];
    [task resume];
}

+ (void)showKeyPromptWithMessage:(NSString *)message prefillKey:(NSString *)prefill {
    UIWindow *window = [self getActiveWindow];
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    if (!rootVC) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showKeyPromptWithMessage:message prefillKey:prefill];
        });
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Teddy Team"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Nhập mã key của bạn...";
        textField.text = prefill ?: @"";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    UIAlertAction *pasteAction = [UIAlertAction actionWithTitle:@"Dán & Xác nhận" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *pastedString = [[UIPasteboard generalPasteboard].string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (pastedString.length > 0) {
            [[NSUserDefaults standardUserDefaults] setObject:pastedString forKey:SAVED_KEY_PREF];
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:FIRST_LOGIN_ALERT];
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:IS_VERIFIED_BEFORE];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self checkLicense];
        } else {
            [self showKeyPromptWithMessage:@"Bộ nhớ tạm đang trống, vui lòng copy key trước!" prefillKey:prefill];
        }
    }];

    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Xác nhận" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *inputKey = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (inputKey.length > 0) {
            [[NSUserDefaults standardUserDefaults] setObject:inputKey forKey:SAVED_KEY_PREF];
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:FIRST_LOGIN_ALERT];
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:IS_VERIFIED_BEFORE];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self checkLicense];
        } else {
            [self showKeyPromptWithMessage:@"Vui lòng không để trống ô nhập Key!" prefillKey:nil];
        }
    }];

    [alert addAction:pasteAction];
    [alert addAction:confirmAction];
    [rootVC presentViewController:alert animated:YES completion:nil];
}

+ (void)showInfoAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIWindow *window = [self getActiveWindow];
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    if (!rootVC) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Bắt đầu sử dụng" style:UIAlertActionStyleCancel handler:nil]];
    [rootVC presentViewController:alert animated:YES completion:nil];
}

@end

// Lắng nghe sự kiện app khởi động xong để đảm bảo UIWindow đã sẵn sàng hiện popup
static void __attribute__((constructor)) initialize(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [KeyManager checkLicense];
        });
    }];
}
