#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "ABKInAppMessageViewController.h"
#import "ABKInAppMessageHTMLJSBridge.h"

NS_ASSUME_NONNULL_BEGIN
static NSString *const ABKInAppMessageHTMLFileName = @"message.html";

@interface ABKInAppMessageHTMLBaseViewController : ABKInAppMessageViewController <WKNavigationDelegate, WKUIDelegate>

/*!
 * The WKWebView used to parse and display the HTML.
 */
@property (nonatomic) WKWebView *webView;

@property (nonatomic) ABKInAppMessageHTMLJSBridge *javascriptInterface;

/*!
 * The constraints for top and bottom between view and the super view.
 */
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *topConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *bottomConstraint;

@end
NS_ASSUME_NONNULL_END
