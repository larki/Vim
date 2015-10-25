/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				   iOS port by Romain Goyet
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * gui_ios.m
 *
 * Support for the iOS GUI. Most of the iOS code resides in this file.
 */

#import "vim.h"
#import <UIKit/UIKit.h>

#define RGB(r,g,b)	((r) << 16) + ((g) << 8) + (b)
#define ARRAY_LENGTH(a) (sizeof(a) / sizeof(a[0]))

static int hex_digit(int c) {
    if (VIM_ISDIGIT(c))
        return c - '0';
    c = TOLOWER_ASC(c);
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    return -1000;
}

void CGLayerCopyRectToRect(CGLayerRef layer, CGRect sourceRect, CGRect targetRect);
CGColorRef CGColorCreateFromVimColor(guicolor_T color);
@class VimViewController;
@class VimTextView;

struct {
    UIWindow * window;
    VimViewController * view_controller;
    CGRect dirtyRect;
    CGLayerRef layer;
    CGColorRef fg_color;
    CGColorRef bg_color;
    int        blink_state;
    long       blink_wait;
    long       blink_on;
    long       blink_off;
    NSTimer *  blink_timer;
    NSDate  * lastKeyPress;
} gui_ios;

enum blink_state {
    BLINK_NONE,     /* not blinking at all */
    BLINK_OFF,      /* blinking, cursor is not shown */
    BLINK_ON        /* blinking, cursor is shown */
};

#pragma mark -
#pragma mark VimTextView

@interface VimTextView : UIView {
}
- (void)resizeShell;
@end

@implementation VimTextView
- (void)dealloc {
    if (gui_ios.layer) {
        CGLayerRelease(gui_ios.layer);
        gui_ios.layer = NULL;
    }
    [super dealloc];
}

- (void)drawRect:(CGRect)rect {
    if (gui_ios.layer != NULL) {
        if(!CGRectEqualToRect(rect, CGRectZero)) {
            CGContextRef context = UIGraphicsGetCurrentContext();
            CGContextSaveGState(context);
            CGContextBeginPath(context);
            CGContextAddRect(context, rect);
            CGContextClip(context);
            CGRect bounds = CGRectMake(0, 0, 1024, 1024);


            CGContextDrawLayerInRect(context, bounds, gui_ios.layer);
//            CGContextDrawLayerAtPoint(context, rect.origin, gui_ios.layer);
            CGContextRestoreGState(context);
            gui_ios.dirtyRect = CGRectZero;
        }
    } else {
        gui_ios.layer = CGLayerCreateWithContext(UIGraphicsGetCurrentContext(), CGSizeMake(2048.0f, 2048.0f), nil);
        CGContextRef layerContext = CGLayerGetContext(gui_ios.layer);
        CGContextScaleCTM(layerContext, 2, 2);
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self resizeShell];
}

- (void)resizeShell {
    NSLog(@"Setting shell size to %d x %d", (int)self.bounds.size.width, (int)self.bounds.size.height);
    /*for (NSString* family in [UIFont familyNames])
    {
        NSLog(@"%@", family);
        for(NSString* name in [UIFont fontNamesForFamilyName: family])
        {
            NSLog(@" %@",name);
        }
    }
    */
    gui_resize_shell(self.bounds.size.width, self.bounds.size.height);
}
@end

#pragma mark -
#pragma mark VimViewController

@interface VimViewController : UIViewController <UIKeyInput, UITextInputTraits> {
    VimTextView * _textView;
    UIView * _dialogView;
    UILabel * _countLabel;
    BOOL _hasBeenFlushedOnce;
}


@property (nonatomic, readonly) VimTextView * textView;
- (void)resizeShell;
- (void)flush;
- (void)blinkCursorTimer:(NSTimer *)timer;
- (void)handleButton:(UIBarButtonItem *) sender;

//@property (nonatomic, readonly) UILabel * dialogView;
@end


@implementation VimViewController

@synthesize textView = _textView;
//@synthesize dialogView = _dialogView;


#pragma mark UIResponder
- (BOOL)canBecomeFirstResponder {
    return _hasBeenFlushedOnce;
//    return YES;
}

- (BOOL)canResignFirstResponder {
    return YES;
}

#pragma mark UIViewController
- (BOOL)prefersStatusBarHidden {
    return YES;
}
- (void)loadView {
    self.view = [[[UIView alloc] initWithFrame:gui_ios.window.bounds] autorelease];
    self.view.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);

    CGFloat statusBarHeight = [UIApplication sharedApplication].statusBarFrame.size.height;
    if (UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
        statusBarHeight = [UIApplication sharedApplication].statusBarFrame.size.height  ;
    }
    //CGFloat statusBarOffset = statusBarHeight;
    CGFloat statusBarOffset = statusBarHeight;
    _textView = [[VimTextView alloc] initWithFrame:CGRectMake(0.0f, statusBarOffset, self.view.bounds.size.width, self.view.bounds.size.height - statusBarOffset)];
    NSLog(@"%f",self.view.bounds.size.height);
    _textView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    [self.view addSubview:_textView];
    /*_countLabel = [[UILabel alloc] initWithFrame:CGRectMake(500, 10, 500, 15)];
    _countLabel.text = @"Test: ";
    _countLabel.font=[UIFont boldSystemFontOfSize:15.0];
    _countLabel.textColor=[UIColor whiteColor];
    _countLabel.backgroundColor=[UIColor clearColor];
    [self.view addSubview:_countLabel];*/
    [_textView release];

    _hasBeenFlushedOnce = NO;

}

- (void)viewDidLoad {
    [super viewDidLoad];

    UITapGestureRecognizer * tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(click:)];
    [_textView addGestureRecognizer:tapGestureRecognizer];
    [tapGestureRecognizer release];
    
    UILongPressGestureRecognizer * longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];

    [_textView addGestureRecognizer:longPressGestureRecognizer];
    [longPressGestureRecognizer release];

    UIPanGestureRecognizer * panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    panGestureRecognizer.minimumNumberOfTouches = 2;
    panGestureRecognizer.maximumNumberOfTouches = 2;
    [_textView addGestureRecognizer:panGestureRecognizer];
    [panGestureRecognizer release];

    UIPanGestureRecognizer * scrollGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scroll:)];
    scrollGestureRecognizer.minimumNumberOfTouches = 1;
    scrollGestureRecognizer.maximumNumberOfTouches = 1;
    [_textView addGestureRecognizer:scrollGestureRecognizer];
    [scrollGestureRecognizer release];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWasShown:)
                                                 name:UIKeyboardDidShowNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillBeHidden:)
                                                 name:UIKeyboardWillHideNotification object:nil];
    UITextInputAssistantItem *inputAssistantItem = [self inputAssistantItem];
    inputAssistantItem.leadingBarButtonGroups = @[];
    inputAssistantItem.trailingBarButtonGroups = @[];
    

    
    
}

- (void)viewDidUnload {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidShowNotification object:nil];

    for (UIGestureRecognizer * gestureRecognizer in _textView.gestureRecognizers) {
        [_textView removeGestureRecognizer:gestureRecognizer];
    }

    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return YES;
}

#pragma mark UIKeyInput
- (BOOL)hasText {
    return NO;
}
- (NSArray<UIKeyCommand *>*)keyCommands {
    return @[
             [UIKeyCommand keyCommandWithInput:@"[" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"l" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"w" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"]" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"f" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"b" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"e" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"y" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"j" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"k" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"v" modifierFlags:UIKeyModifierControl action:@selector(handleCTRL:)],
             [UIKeyCommand keyCommandWithInput:@"j" modifierFlags:NULL action:@selector(handleNULL:)],
             [UIKeyCommand keyCommandWithInput:@"k" modifierFlags:NULL action:@selector(handleNULL:)],
             [UIKeyCommand keyCommandWithInput:@"l" modifierFlags:NULL action:@selector(handleNULL:)],
             [UIKeyCommand keyCommandWithInput:@"h" modifierFlags:NULL action:@selector(handleNULL:)],
             [UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:NULL action:@selector(handleNULL:)],
             [UIKeyCommand keyCommandWithInput:UIKeyInputUpArrow modifierFlags:NULL action:@selector(handleNULL:)],
             [UIKeyCommand keyCommandWithInput:UIKeyInputDownArrow modifierFlags:NULL action:@selector(handleNULL:)],
             [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow modifierFlags:NULL action:@selector(handleNULL:)],
             [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow modifierFlags:NULL action:@selector(handleNULL:)],
             
             [UIKeyCommand keyCommandWithInput:@"-" modifierFlags:UIKeyModifierControl action:@selector(testHandler:)]/* discoverabilityTitle:@"Protocols"],
             [UIKeyCommand keyCommandWithInput:@"3" modifierFlags:UIKeyModifierCommand action:@selector(selectTab:) discoverabilityTitle:@"Functions"],
             [UIKeyCommand keyCommandWithInput:@"4" modifierFlags:UIKeyModifierCommand action:@selector(selectTab:) discoverabilityTitle:@"Operators"],
             
             [UIKeyCommand keyCommandWithInput:@"f"
                                 modifierFlags:UIKeyModifierCommand | UIKeyModifierAlternate
                                        action:@selector(search:)
                          discoverabilityTitle:@"Find…"]*/
             ];
}


- (void) testHandler:(UIKeyCommand *) sender {
    [self insertText:sender.input];
    NSLog(@"input: %@",sender.input);
}

- (void) handleButton:(UIBarButtonItem *)sender{
    NSLog(@"button pressed %@", sender.title);

    char command[255];
    if([sender.title isEqualToString:@"ESC"]) {
        command[0] = ESC;
        command[1] = 0x0;
    }
    add_to_input_buf(command,1);
    
    
}

- (void) handleNULL:(UIKeyCommand *) sender {
    NSLog(@"input: %@",sender.input);
    gui_ios.lastKeyPress = [[NSDate alloc] initWithTimeIntervalSinceNow:0];

    char command[255];
    if([sender.input isEqualToString:@"j"])
    {
        command[0] = 'j';
        command[1] = 0x0;
    }
    else if([sender.input isEqualToString:@"l"]) {
        command[0] = 'l';
        command[1] = 0x0;
    }
    else if([sender.input isEqualToString:@"h"]) {
        command[0] = 'h';
        command[1] = 0x0;
    }
    else if([sender.input isEqualToString:@"k"]) {
        command[0] = 'k';
        command[1] = 0x0;
    }
    else if([sender.input isEqualToString:UIKeyInputUpArrow]) {
        command[0] = K_UP;
        command[1] = 0x0;
    }
    else if([sender.input isEqualToString:UIKeyInputDownArrow]) {
        command[0] = K_DOWN;
        command[1] = 0x0;
    }
    else if([sender.input isEqualToString:UIKeyInputLeftArrow]) {
        command[0] = K_LEFT;
        command[1] = 0x0;
    }
    else if([sender.input isEqualToString:UIKeyInputRightArrow]) {
        command[0] = K_RIGHT;
        command[1] = 0x0;
    }
    else if([sender.input isEqualToString:UIKeyInputEscape])
    {
        command[0] = ESC;
        command[1] = 0x0;
    }
    

    //[self insertText:sender.input];
   // NSUInteger length =[sender.input lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    //add_to_input_buf((char_u*) sender.input, length);
    add_to_input_buf(command,1);
    [_textView setNeedsDisplayInRect:gui_ios.dirtyRect];


}
- (void) handleCTRL:(UIKeyCommand *) sender {
    char command[255];
    if([sender.input isEqualToString:@"["])
    {
        command[0] = ESC;
        command[1] = 0x0;
    }
    if([sender.input isEqualToString:@"]"])
    {
        command[0] = Ctrl_RSB;
        command[1] = 0x0;
    }
    if([sender.input isEqualToString:@"l"]) {
        command[0] = Ctrl_L;
        command[1] = 0x0;
    }
    if([sender.input isEqualToString:@"w"]) {
        command[0] = Ctrl_W;
        command[1] = 0x0;
    }
    if([sender.input isEqualToString:@"f"]) {
        command[0] = Ctrl_F;
        command[1] = 0x0;
    }
    if([sender.input isEqualToString:@"b"]) {
        command[0] = Ctrl_B;
        command[1] = 0x0;
    }
    if([sender.input isEqualToString:@"e"]) {
        command[0] = Ctrl_E;
        command[1] = 0x0;
    }
    if([sender.input isEqualToString:@"y"]) {
        command[0] = Ctrl_Y;
        command[1] = 0x0;
    }
    if([sender.input isEqualToString:@"j"]) {
        command[0] = Ctrl_J;
        command[1] = 0x0;
    }
    if([sender.input isEqualToString:@"k"]) {
        command[0] = Ctrl_K;
        command[1] = 0x0;
    }
  
   add_to_input_buf(command, 1);
    [_textView setNeedsDisplayInRect:gui_ios.dirtyRect];
   

    
    
    //NSString * text = @"l";
//    add_to_input_buf_csi((char_u *)[text UTF8String], [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    //[_textView setNeedsDisplayInRect:gui_ios.dirtyRect];
    //[self insertText:text];
    //NSLog(@"%@", text);
}
- (void)insertText:(NSString *)text {
    if([text isEqualToString:@"\n"]){
        NSLog(@"Enter!!");
        char escapeString[] = {CAR, 0};
        text = [NSString stringWithUTF8String:escapeString];
    }
    int length =[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    add_to_input_buf((char_u *)[text UTF8String],length );
    [_textView setNeedsDisplayInRect:gui_ios.dirtyRect];
}

- (void)deleteBackward {
    char escapeString[] = {BS, 0};
    [self insertText:[NSString stringWithUTF8String:escapeString]];
}

#pragma mark UITextInputTraits
- (UITextAutocapitalizationType)autocapitalizationType {
    return UITextAutocapitalizationTypeNone;
}

- (UIKeyboardType)keyboardType {
    return UIKeyboardTypeDefault;
}

- (UITextAutocorrectionType)autocorrectionType {
    return UITextAutocorrectionTypeNo;
}


//- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
//    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
//        NSString *alertMessage = [NSString stringWithFormat:@"Successfully imported %@", [url lastPathComponent]];
//        dispatch_async(dispatch_get_main_queue(), ^{
//            UIAlertController *alertController = [UIAlertController
//                                                  alertControllerWithTitle:@"Import"
//                                                  message:alertMessage
//                                                  preferredStyle:UIAlertControllerStyleAlert];
//            [alertController addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:nil]];
//            [self presentViewController:alertController animated:YES completion:nil];
//        });
//    }
//}

#pragma mark VimViewController
- (void)click:(UITapGestureRecognizer *)sender {
    [self becomeFirstResponder];
    CGPoint clickLocation = [sender locationInView:sender.view];
    gui_send_mouse_event(MOUSE_LEFT, clickLocation.x, clickLocation.y, 1, 0);
}

- (void)longPress:(UILongPressGestureRecognizer *)sender {
     if (sender.state == UIGestureRecognizerStateBegan) {
    [self becomeFirstResponder];
 //   CGPoint clickLocation = [sender locationInView:sender.view];
    NSLog(@"Longpress");
    
     UITextInputAssistantItem *inputAssistantItem = [self inputAssistantItem];
    
    
    if([inputAssistantItem.leadingBarButtonGroups count]==0) {
    UIBarButtonItem *escButton = [[UIBarButtonItem alloc] initWithTitle:@"ESC" style:UIBarButtonItemStylePlain target:self action:@selector(handleButton:)];
    NSArray *barButtonItems = [[NSArray alloc] initWithObjects:escButton, nil];
    UIBarButtonItemGroup *group = [[UIBarButtonItemGroup alloc] initWithBarButtonItems:barButtonItems representativeItem:nil];
   
    inputAssistantItem.leadingBarButtonGroups = @[group];
    inputAssistantItem.trailingBarButtonGroups = @[];

    }
    else {
        inputAssistantItem.leadingBarButtonGroups = @[];
        inputAssistantItem.trailingBarButtonGroups = @[];
        
    }
    [self resignFirstResponder];
    [self becomeFirstResponder];
     }



    /*UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.image"]
                                                                                                                inMode:UIDocumentPickerModeImport];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];*/
    
    //do_cmdline_cmd
    //NSURL *url = [self fileToURL:self.textView.];
    //NSLOg(url.absoluteString);
    
}



- (void)pan:(UIPanGestureRecognizer *)sender {
    CGPoint clickLocation = [sender locationInView:sender.view];
    
    int event = MOUSE_DRAG;
    switch (sender.state) {
        case UIGestureRecognizerStateBegan:
            event = MOUSE_LEFT;
            break;
        case UIGestureRecognizerStateEnded:
            event = MOUSE_RELEASE;
            break;
        default:
            event = MOUSE_DRAG;
            break;
    }
    gui_send_mouse_event(event, clickLocation.x, clickLocation.y, 1, 0);
}

- (void)scroll:(UIPanGestureRecognizer *)sender {
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        [self resignFirstResponder];
    }
    CGPoint clickLocation = [sender locationInView:sender.view];
    CGPoint translation = [sender translationInView:sender.view];
    static int totalScrollX = 0;
    static int totalScrollY = 0;
    if (sender.state == UIGestureRecognizerStateBegan) {
        totalScrollX = 0;
        totalScrollY = 0;
    }
    int targetScrollX = translation.x / gui.char_width;
    int targetScrollY = translation.y / gui.char_height;

    while (targetScrollX < totalScrollX) {
        gui_send_mouse_event(MOUSE_6, clickLocation.x, clickLocation.y, 0, 0);
        totalScrollX--;
    }
    while (targetScrollX > totalScrollX) {
        gui_send_mouse_event(MOUSE_7, clickLocation.x, clickLocation.y, 0, 0);
        totalScrollX++;
    }
    while (targetScrollY < totalScrollY) {
        gui_send_mouse_event(MOUSE_5, clickLocation.x, clickLocation.y, 0, 0);
        totalScrollY--;
    }
    while (targetScrollY > totalScrollY) {
        gui_send_mouse_event(MOUSE_4, clickLocation.x, clickLocation.y, 0, 0);
        totalScrollY++;
    }
}

- (void)keyboardWasShown:(NSNotification *)notification {
    CGRect keyboardRect = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardRectInView = [self.view.window convertRect:keyboardRect toView:_textView];
    _textView.frame = CGRectMake(_textView.frame.origin.x,
                                 _textView.frame.origin.y,
                                 _textView.frame.size.width,
                                 keyboardRectInView.origin.y);
    CGRect keyboard = [self.view convertRect:keyboardRect fromView:self.view.window];
    CGFloat height = self.view.frame.size.height;
    
   /* External keyboard or not?
   
    if ((keyboard.origin.y + keyboard.size.height) > height) {
        NSLog(@"External!");
     
    }
    else {
        NSLog(@"Virtual");
    }

    */

}

- (void)keyboardWillBeHidden:(NSNotification *)notification {
    CGRect keyboardRect = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardRectInView = [self.view.window convertRect:keyboardRect toView:_textView];
    _textView.frame = CGRectMake(_textView.frame.origin.x,
                                 _textView.frame.origin.y,
                                 _textView.frame.size.width,
                                 keyboardRectInView.origin.y);
    NSLog(@"hidden");
}

- (void)resizeShell {
    [_textView resizeShell];
}

- (void)flush {
    if(_hasBeenFlushedOnce!=YES) {
        _hasBeenFlushedOnce = YES;
        [self becomeFirstResponder];
    }
    [_textView setNeedsDisplayInRect:gui_ios.dirtyRect];
}

- (void)blinkCursorTimer:(NSTimer *)timer {
    NSTimeInterval on_time, off_time;
    
    
    [gui_ios.blink_timer invalidate];
    if (gui_ios.blink_state == BLINK_ON) {
        gui_undraw_cursor();
        gui_ios.blink_state = BLINK_OFF;
        
        off_time = gui_ios.blink_off / 1000.0;
        gui_ios.blink_timer = [NSTimer scheduledTimerWithTimeInterval:off_time
                                                               target:self
                                                             selector:@selector(blinkCursorTimer:)
                                                             userInfo:nil
                                                              repeats:NO];
    }
    else if (gui_ios.blink_state == BLINK_OFF) {
        gui_update_cursor(TRUE, FALSE);
        gui_ios.blink_state = BLINK_ON;
        
        on_time = gui_ios.blink_on / 1000.0;
        gui_ios.blink_timer = [NSTimer scheduledTimerWithTimeInterval:on_time
                                                               target:self
                                                             selector:@selector(blinkCursorTimer:)
                                                             userInfo:nil
                                                              repeats:NO];
    }
    [_textView setNeedsDisplayInRect:gui_ios.dirtyRect];
}

@end

#pragma mark -
#pragma mark VimAppDelegate

@interface VimAppDelegate : NSObject <UIApplicationDelegate> {
}
@end

@implementation VimAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Per Apple's documentation : Performs the specified selector on the application's main thread during that thread's next run loop cycle.

    NSURL* url = nil;
    if (launchOptions && launchOptions.count) {
        // Someone asked us to restart the application
        // Need to extract the URL to open
        url = [launchOptions valueForKey:UIApplicationLaunchOptionsURLKey];
    }

    gui_ios.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    gui_ios.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    gui_ios.view_controller = [[VimViewController alloc] init];
    gui_ios.window.rootViewController = gui_ios.view_controller;
    [gui_ios.view_controller release];
    [gui_ios.window makeKeyAndVisible];
    gui_ios.lastKeyPress = [[NSDate alloc] initWithTimeIntervalSinceNow:0];
    [gui_ios.view_controller becomeFirstResponder];


    [self performSelectorOnMainThread:@selector(_VimMain:) withObject:url waitUntilDone:NO];

    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if ([gui_ios.view_controller canBecomeFirstResponder]) {
        NSString* urlString = url.absoluteString;
        if (url.isFileURL) {
            // Find "Documents/" in the urlString.
            NSRange position = [urlString rangeOfString:@"Documents/"];
            if (position.location == NSNotFound) return NO;
            position.location += position.length;
            position.length = [urlString length] - position.location;
            NSString* fileName = [urlString substringWithRange:position];
            char command[255];
            sprintf(command, "tabedit %s", [fileName UTF8String]);
            do_cmdline_cmd((char_u *)command);
            command[0] = Ctrl_L;
            command[1] = 0x0;
            add_to_input_buf(command, 1);
            return YES;
        }
    }
    return NO;
}

- (void)_VimMain:(NSURL *)url {
    NSString * vimPath = [[NSBundle mainBundle] resourcePath];
    vim_setenv((char_u *)"VIM", (char_u *)[vimPath UTF8String]);
    vim_setenv((char_u *)"VIMRUNTIME", (char_u *)[[vimPath stringByAppendingPathComponent:@"runtime"] UTF8String]);

    NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        vim_setenv((char_u *)"HOME", (char_u *)[[paths objectAtIndex:0] UTF8String]);

        [[NSFileManager defaultManager] changeCurrentDirectoryPath:[paths objectAtIndex:0]];
    }
    
    char * argv[2] = { "vim", nil};
    int numArgs = 1;
    if (url && (url != nil) && (url.isFileURL)) {
        // Need to find the file name
        // Find "Documents/" in the urlString.
        NSString* urlString = url.absoluteString;
        NSRange position = [urlString rangeOfString:@"Documents/"];
        if (position.location != NSNotFound) {
            position.location += position.length;
            position.length = [urlString length] - position.location;
            char* fileName = [[urlString substringWithRange:position] UTF8String];
            argv[1] = fileName;
            numArgs += 1;
        }
    }

    VimMain(numArgs, argv);
}
@end



#pragma mark -
#pragma mark Helper C functions

void CGLayerCopyRectToRect(CGLayerRef layer, CGRect sourceRect, CGRect targetRect) {
    CGContextRef context = CGLayerGetContext(layer);
    
    CGRect destinationRect = targetRect;
    destinationRect.size.width = MIN(targetRect.size.width, sourceRect.size.width);
    destinationRect.size.height = MIN(targetRect.size.height, sourceRect.size.height);
    
    CGContextSaveGState(context);
    
    CGContextBeginPath(context);
    CGContextAddRect(context, destinationRect);
    CGContextClip(context);
    CGSize size = CGLayerGetSize(layer);
    
    CGContextDrawLayerInRect(context, CGRectMake(destinationRect.origin.x - sourceRect.origin.x, destinationRect.origin.y - sourceRect.origin.y, size.width/2, size.height/2),layer);
//    CGContextDrawLayerAtPoint(context, CGPointMake(destinationRect.origin.x - sourceRect.origin.x, destinationRect.origin.y - sourceRect.origin.y), layer);

    gui_ios.dirtyRect = CGRectUnion(gui_ios.dirtyRect, destinationRect);
    CGContextRestoreGState(context);
}

CGColorRef CGColorCreateFromVimColor(guicolor_T color) {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    int red = (color & 0xFF0000) >> 16;
    int green = (color & 0x00FF00) >> 8;
    int blue = color & 0x0000FF;
    CGFloat rgb[4] = {(float)red/0xFF, (float)green/0xFF, (float)blue/0xFF, 1.0f};
    CGColorRef cgColor = CGColorCreate(colorSpace, rgb);
    CGColorSpaceRelease(colorSpace);
    return cgColor;
}

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int retVal = UIApplicationMain(argc, argv, nil, @"VimAppDelegate");
    [pool release];
    return retVal;
}



#pragma mark -
#pragma mark Vim C functions

/*
 * Parse the GUI related command-line arguments.  Any arguments used are
 * deleted from argv, and *argc is decremented accordingly.  This is called
 * when vim is started, whether or not the GUI has been started.
 * NOTE: This function will be called twice if the Vim process forks.
 */
    void
gui_mch_prepare(int *argc, char **argv)
{
}


/*
 * Check if the GUI can be started.  Called before gvimrc is sourced.
 * Return OK or FAIL.
 */
    int
gui_mch_init_check(void)
{
//    printf("%s\n",__func__);  
    return OK;
}


/*
 * Initialise the GUI.  Create all the windows, set up all the call-backs etc.
 * Returns OK for success, FAIL when the GUI can't be started.
 */
    int
gui_mch_init(void)
{
//    printf("%s\n",__func__);  
    set_option_value((char_u *)"termencoding", 0L, (char_u *)"utf-8", 0);
    
    gui_mch_def_colors();
    
    set_normal_colors();

    gui_check_colors();
    gui.def_norm_pixel = gui.norm_pixel;
    gui.def_back_pixel = gui.back_pixel;

#ifdef FEAT_GUI_SCROLL_WHEEL_FORCE
    gui.scroll_wheel_force = 1;
#endif

    return OK;
}



    void
gui_mch_exit(int rc)
{
//    printf("%s\n",__func__);  
}


/*
 * Open the GUI window which was created by a call to gui_mch_init().
 */
    int
gui_mch_open(void)
{
    [gui_ios.view_controller resizeShell];
//    [gui_ios.window makeKeyAndVisible];
    
//    printf("%s\n",__func__);  
    return OK;
}


// -- Updating --------------------------------------------------------------


/*
 * Catch up with any queued X events.  This may put keyboard input into the
 * input buffer, call resize call-backs, trigger timers etc.  If there is
 * nothing in the X event queue (& no timers pending), then we return
 * immediately.
 */
    void
gui_mch_update(void)
{
    // This function is called extremely often.  It is tempting to do nothing
    // here to avoid reduced frame-rates but then it would not be possible to
    // interrupt Vim by presssing Ctrl-C during lengthy operations (e.g. after
    // entering "10gs" it would not be possible to bring Vim out of the 10 s
    // sleep prematurely).  Furthermore, Vim sometimes goes into a loop waiting
    // for keyboard input (e.g. during a "more prompt") where not checking for
    // input could cause Vim to lock up indefinitely.
    //
    // As a compromise we check for new input only every now and then. Note
    // that Cmd-. sends SIGINT so it has higher success rate at interrupting
    // Vim than Ctrl-C.

//    printf("%s\n",__func__);  
}


/* Flush any output to the screen */
    void
gui_mch_flush(void)
{
    // This function is called way too often to be useful as a hint for
    // flushing.  If we were to flush every time it was called the screen would
    // flicker.
//    printf("%s\n",__func__);
    CGContextFlush(CGLayerGetContext(gui_ios.layer));
    [gui_ios.view_controller flush];
}


/*
 * GUI input routine called by gui_wait_for_chars().  Waits for a character
 * from the keyboard.
 *  wtime == -1	    Wait forever.
 *  wtime == 0	    This should never happen.
 *  wtime > 0	    Wait wtime milliseconds for a character.
 * Returns OK if a character was found to be available within the given time,
 * or FAIL otherwise.
 */
    int
gui_mch_wait_for_chars(int wtime)
{
    NSDate * now = [NSDate date];
    double  passed =[now timeIntervalSinceDate:gui_ios.lastKeyPress]*1000;
    if(passed <1000 )
        wtime=10;
        //wtime = gui_ios.wait;
    if(wtime<0)
        wtime = 4000;
    
   // NSLog(@"Wtime: %i", wtime);
    //NSLog(@"Passed: %f", passed);
    NSDate * expirationDate = wtime > 0 ? [NSDate dateWithTimeIntervalSinceNow:((NSTimeInterval)wtime)/1000.0] : [NSDate distantFuture];
    [[NSRunLoop currentRunLoop] acceptInputForMode:NSDefaultRunLoopMode beforeDate:expirationDate];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01f]]; // This is a workaround. Without this, you cannot split the UIKeyboard
    double delay = [expirationDate timeIntervalSinceNow];

    return delay < 0 ? FAIL : OK;
}


// -- Drawing ---------------------------------------------------------------


/*
 * Clear the whole text window.
 */
void
gui_mch_clear_all(void)
{
//    printf("%s\n",__func__);
    CGContextRef context = CGLayerGetContext(gui_ios.layer);
    
    CGContextSetFillColorWithColor(context, gui_ios.bg_color);
    CGSize size = CGLayerGetSize(gui_ios.layer);
    CGContextFillRect(context, CGRectMake(0.0f, 0.0f, size.width, size.height));
    gui_ios.dirtyRect = gui_ios.view_controller.textView.bounds;
}


/*
 * Clear a rectangular region of the screen from text pos (row1, col1) to
 * (row2, col2) inclusive.
 */
    void
gui_mch_clear_block(int row1, int col1, int row2, int col2)
{
    CGContextRef context = CGLayerGetContext(gui_ios.layer);
    gui_mch_set_bg_color(gui.back_pixel);
    CGContextSetFillColorWithColor(context, gui_ios.bg_color);
    CGRect rect = CGRectMake(FILL_X(col1),
                             FILL_Y(row1),
                             FILL_X(col2+1)-FILL_X(col1),
                             FILL_Y(row2+1)-FILL_Y(row1));
    CGContextFillRect(context, rect);
    gui_ios.dirtyRect = CGRectUnion(gui_ios.dirtyRect, rect);
}


void gui_mch_draw_string(int row, int col, char_u *s, int len, int flags) {
    if (s == NULL || len <= 0) {
        return;
    }

   // NSLog(@"Draw %s ", s);

    CGContextRef context = CGLayerGetContext(gui_ios.layer);

    CGContextSetShouldAntialias(context, p_antialias);
    CGContextSetAllowsAntialiasing(context, p_antialias);
    CGContextSetShouldSmoothFonts(context, p_antialias);

    CGContextSetCharacterSpacing(context, 0.0f);
    CGContextSetTextDrawingMode(context, kCGTextFill); 

    if (!(flags & DRAW_TRANSP)) {
        CGContextSetFillColorWithColor(context, gui_ios.bg_color);
        CGContextFillRect(context, CGRectMake(FILL_X(col), FILL_Y(row), FILL_X(col+len)-FILL_X(col), FILL_Y(row+1)-FILL_Y(row)));
    }

    CGContextSetFillColorWithColor(context, gui_ios.fg_color);

    NSString * string = [[NSString alloc] initWithBytes:s length:len encoding:NSUTF8StringEncoding];
    if (string == nil) {
        return;
    }
    NSDictionary * attributes = [[NSDictionary alloc] initWithObjectsAndKeys:(id)gui.norm_font, (NSString *)kCTFontAttributeName,
                                 [NSNumber numberWithBool:YES], kCTForegroundColorFromContextAttributeName,
                                 nil];
    NSAttributedString * attributedString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    [attributes release];
    [string release];
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)attributedString);
    // Set text position and draw the line into the graphics context
    CGContextSetTextPosition(context, TEXT_X(col), TEXT_Y(row));
    CTLineDraw(line, context);


    if (flags & DRAW_CURSOR) {
        CGContextSaveGState(context);
        CGContextSetBlendMode(context, kCGBlendModeDifference);
        CGContextFillRect(context, CGRectMake(FILL_X(col), FILL_Y(row),
                                              FILL_X(col+len)-FILL_X(col),
                                              FILL_Y(row+1)-FILL_Y(row)));
        CGContextRestoreGState(context);
    }
    if (line != NULL) {
        CFRelease(line);
    }
    [attributedString release];
    CGRect rect = CGRectMake(FILL_X(col),
                             FILL_Y(row),
                             FILL_X(col+len)-FILL_X(col),
                             FILL_Y(row+1)-FILL_Y(row));
    gui_ios.dirtyRect = CGRectUnion(gui_ios.dirtyRect, rect);
}


/*
 * Delete the given number of lines from the given row, scrolling up any
 * text further down within the scroll region.
 */
    void
gui_mch_delete_lines(int row, int num_lines)
{
//    printf("%s\n",__func__);
    CGRect sourceRect = CGRectMake(FILL_X(gui.scroll_region_left),
                                   FILL_Y(row + num_lines),
                                   FILL_X(gui.scroll_region_right+1) - FILL_X(gui.scroll_region_left),
                                   FILL_Y(gui.scroll_region_bot+1) - FILL_Y(row + num_lines));

    CGRect targetRect = CGRectMake(FILL_X(gui.scroll_region_left),
                                   FILL_Y(row),
                                   FILL_X(gui.scroll_region_right+1) - FILL_X(gui.scroll_region_left),
                                   FILL_Y(gui.scroll_region_bot+1) - FILL_Y(row + num_lines));

    CGLayerCopyRectToRect(gui_ios.layer, sourceRect, targetRect);

    gui_clear_block(gui.scroll_region_bot - num_lines + 1,
                    gui.scroll_region_left,
                    gui.scroll_region_bot, gui.scroll_region_right);
}


/*
 * Insert the given number of lines before the given row, scrolling down any
 * following text within the scroll region.
 */
    void
gui_mch_insert_lines(int row, int num_lines)
{
//    printf("%s\n",__func__);
    CGRect sourceRect = CGRectMake(FILL_X(gui.scroll_region_left),
                                   FILL_Y(row),
                                   FILL_X(gui.scroll_region_right+1) - FILL_X(gui.scroll_region_left),
                                   FILL_Y(gui.scroll_region_bot+1) - FILL_Y(row + num_lines));

    CGRect targetRect = CGRectMake(FILL_X(gui.scroll_region_left),
                                   FILL_Y(row + num_lines),
                                   FILL_X(gui.scroll_region_right+1) - FILL_X(gui.scroll_region_left),
                                   FILL_Y(gui.scroll_region_bot+1) - FILL_Y(row + num_lines));
    
    CGLayerCopyRectToRect(gui_ios.layer, sourceRect, targetRect);

    gui_clear_block(row, gui.scroll_region_left,
                    row + num_lines - 1, gui.scroll_region_right);
}

/*
 * Set the current text foreground color.
 */
    void
gui_mch_set_fg_color(guicolor_T color)
{
    if (gui_ios.fg_color != NULL) {
        CGColorRelease(gui_ios.fg_color);
    }
    gui_ios.fg_color = CGColorCreateFromVimColor(color);
}


/*
 * Set the current text background color.
 */
    void
gui_mch_set_bg_color(guicolor_T color)
{
    if (gui_ios.bg_color != NULL) {
        CGColorRelease(gui_ios.bg_color);
    }
    gui_ios.bg_color = CGColorCreateFromVimColor(color);
}

/*
 * Set the current text special color (used for underlines).
 */
    void
gui_mch_set_sp_color(guicolor_T color)
{
//    printf("%s\n",__func__);  
}


/*
 * Set default colors.
 */
void gui_mch_def_colors() {
    gui.norm_pixel = gui_mch_get_color((char_u *)"white");
    gui.back_pixel = gui_mch_get_color((char_u *)"black");
    gui.def_back_pixel = gui.back_pixel;
    gui.def_norm_pixel = gui.norm_pixel;
}


/*
 * Called when the foreground or background color has been changed.
 */
    void
gui_mch_new_colors(void)
{
//    printf("%s\n",__func__);  
//    gui.def_back_pixel = gui.back_pixel;
//    gui.def_norm_pixel = gui.norm_pixel;

}

/*
 * Invert a rectangle from row r, column c, for nr rows and nc columns.
 */
    void
gui_mch_invert_rectangle(int r, int c, int nr, int nc)
{
//    printf("%s\n",__func__);  
}

// -- Menu ------------------------------------------------------------------


/*
 * A menu descriptor represents the "address" of a menu as an array of strings.
 * E.g. the menu "File->Close" has descriptor { "File", "Close" }.
 */
   void
gui_mch_add_menu(vimmenu_T *menu, int idx)
{
//    printf("%s\n",__func__);  
}


/*
 * Add a menu item to a menu
 */
    void
gui_mch_add_menu_item(vimmenu_T *menu, int idx)
{
//    printf("%s\n",__func__);  
}


/*
 * Destroy the machine specific menu widget.
 */
    void
gui_mch_destroy_menu(vimmenu_T *menu)
{
//    printf("%s\n",__func__);  
}


/*
 * Make a menu either grey or not grey.
 */
    void
gui_mch_menu_grey(vimmenu_T *menu, int grey)
{
}


/*
 * Make menu item hidden or not hidden
 */
    void
gui_mch_menu_hidden(vimmenu_T *menu, int hidden)
{
//    printf("%s\n",__func__);  
}


/*
 * This is called when user right clicks.
 */
    void
gui_mch_show_popupmenu(vimmenu_T *menu)
{
//    printf("%s\n",__func__);  
}


/*
 * This is called when a :popup command is executed.
 */
    void
gui_make_popup(char_u *path_name, int mouse_pos)
{
//    printf("%s\n",__func__);  
}


/*
 * This is called after setting all the menus to grey/hidden or not.
 */
    void
gui_mch_draw_menubar(void)
{
}


    void
gui_mch_enable_menu(int flag)
{
}

    void
gui_mch_set_menu_pos(int x, int y, int w, int h)
{
//    printf("%s\n",__func__);  
    
    /*
     * The menu is always at the top of the screen.
     */
}

    void
gui_mch_show_toolbar(int showit)
{
//    printf("%s\n",__func__);  
}




// -- Fonts -----------------------------------------------------------------


/*
 * If a font is not going to be used, free its structure.
 */
    void
gui_mch_free_font(font)
    GuiFont	font;
{
//    printf("%s\n",__func__);  
}


    GuiFont
gui_mch_retain_font(GuiFont font)
{
//    printf("%s\n",__func__);  
    return font;
}


/*
 * Get a font structure for highlighting.
 */
    GuiFont
gui_mch_get_font(char_u *name, int giveErrorIfMissing)
{
//    printf("%s\n",__func__);  

    return NOFONT;
}


#if defined(FEAT_EVAL) || defined(PROTO)
/*
 * Return the name of font "font" in allocated memory.
 * TODO: use 'font' instead of 'name'?
 */
    char_u *
gui_mch_get_fontname(GuiFont font, char_u *name)
{
    return name ? vim_strsave(name) : NULL;
}
#endif


/*
 * Initialise vim to use the font with the given name.	Return FAIL if the font
 * could not be loaded, OK otherwise.
 */
    int
gui_mch_init_font(char_u *font_name, int fontset) {
//    printf("%s\n",__func__);

    NSString * normalizedFontName = @"Menlo";
    CGFloat normalizedFontSize = 14.0f;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        normalizedFontSize = 12.0f;
    }
    if (font_name != NULL) {
        NSString * sourceFontName = [[NSString alloc] initWithUTF8String:(const char *)font_name];
        NSRange separatorRange = [sourceFontName rangeOfString:@":h"];
        if (separatorRange.location != NSNotFound) {
            normalizedFontName = [sourceFontName substringToIndex:separatorRange.location];
            normalizedFontSize = [[sourceFontName substringFromIndex:separatorRange.location+separatorRange.length] floatValue];
        }
        [sourceFontName release];
    }
    CTFontRef rawFont = CTFontCreateWithName((CFStringRef)normalizedFontName, normalizedFontSize, &CGAffineTransformIdentity);

    
    CGRect boundingRect = CGRectZero;
    CGGlyph glyph = CTFontGetGlyphWithName(rawFont, (CFStringRef)@"0");
    CTFontGetBoundingRectsForGlyphs(rawFont, kCTFontHorizontalOrientation, &glyph, &boundingRect, 1);

//    NSLog(@"Font bounding box for character 0 : %@", NSStringFromCGRect(boundingRect));
//    NSLog(@"Ascent = %.2f", CTFontGetAscent(rawFont));
//    NSLog(@"Computed height = %.2f", CTFontGetAscent(rawFont) + CTFontGetDescent(rawFont));
//    NSLog(@"Leading = %.2f", CTFontGetLeading(rawFont));
    
    CGSize advances = CGSizeZero;
    
    CTFontGetAdvancesForGlyphs(rawFont, kCTFontHorizontalOrientation, &glyph, &advances, 1);
//    NSLog(@"Advances = %@", NSStringFromCGSize(advances));

    gui.char_ascent = CTFontGetAscent(rawFont);
    gui.char_width = boundingRect.size.width;
    gui.char_height = boundingRect.size.height + 3.0f;
//    gui.char_height = CTFontGetAscent(rawFont) + CTFontGetDescent(rawFont);

    if (gui.norm_font != NULL) {
        CFRelease(gui.norm_font);
    }
    // Now let's rescale the font
    CGAffineTransform transform = CGAffineTransformMakeScale(boundingRect.size.width/advances.width, -1.0f);
    gui.norm_font = CTFontCreateCopyWithAttributes(rawFont,
                                                  normalizedFontSize,
                                                  &transform,
                                                  NULL);
    CFRelease(rawFont);
    
    return OK;
}


/*
 * Set the current text font.
 */
    void
gui_mch_set_font(GuiFont font)
{
//    printf("%s\n",__func__);  
}


// -- Scrollbars ------------------------------------------------------------

// NOTE: Even though scrollbar identifiers are 'long' we tacitly assume that
// they only use 32 bits (in particular when compiling for 64 bit).  This is
// justified since identifiers are generated from a 32 bit counter in
// gui_create_scrollbar().  However if that code changes we may be in trouble
// (if ever that many scrollbars are allocated...).  The reason behind this is
// that we pass scrollbar identifers over process boundaries so the width of
// the variable needs to be fixed (and why fix at 64 bit when only 32 are
// really used?).

    void
gui_mch_create_scrollbar(
	scrollbar_T *sb,
	int orient)	/* SBAR_VERT or SBAR_HORIZ */
{
//    printf("%s\n",__func__);  
}


    void
gui_mch_destroy_scrollbar(scrollbar_T *sb)
{
//    printf("%s\n",__func__);  
}


    void
gui_mch_enable_scrollbar(
	scrollbar_T	*sb,
	int		flag)
{
//    printf("%s\n",__func__);  
}


    void
gui_mch_set_scrollbar_pos(
	scrollbar_T *sb,
	int x,
	int y,
	int w,
	int h)
{
//    printf("%s\n",__func__);  
}


    void
gui_mch_set_scrollbar_thumb(
	scrollbar_T *sb,
	long val,
	long size,
	long max)
{
//    printf("%s\n",__func__);  
}


// -- Cursor ----------------------------------------------------------------


/*
 * Draw a cursor without focus.
 */
    void
gui_mch_draw_hollow_cursor(guicolor_T color)
{
    int w = 1;
    
#ifdef FEAT_MBYTE
    if (mb_lefthalve(gui.row, gui.col))
        w = 2;
#endif
    
    CGContextRef context = CGLayerGetContext(gui_ios.layer);
    CGColorRef cgColor = CGColorCreateFromVimColor(color);
    CGContextSetStrokeColorWithColor(context, cgColor);
    CGColorRelease(cgColor);
    CGRect rect = CGRectMake(FILL_X(gui.col), FILL_Y(gui.row), w * gui.char_width, gui.char_height);
    CGContextStrokeRect(context, rect);
    gui_ios.dirtyRect = CGRectUnion(gui_ios.dirtyRect, rect);
    [gui_ios.view_controller.view setNeedsDisplayInRect:gui_ios.dirtyRect];
}


/*
 * Draw part of a cursor, only w pixels wide, and h pixels high.
 */
    void
gui_mch_draw_part_cursor(int w, int h, guicolor_T color)
{
    CGContextRef context = CGLayerGetContext(gui_ios.layer);
    gui_mch_set_fg_color(color);
    
    int    left;
    
#ifdef FEAT_RIGHTLEFT
    /* vertical line should be on the right of current point */
    if (CURSOR_BAR_RIGHT)
        left = FILL_X(gui.col + 1) - w;
    else
#endif
        left = FILL_X(gui.col);
    
    CGContextSetFillColorWithColor(context, gui_ios.fg_color);
    CGRect rect = CGRectMake(left, FILL_Y(gui.row), (CGFloat)w, (CGFloat)h);
    CGContextFillRect(context, rect);
    gui_ios.dirtyRect = CGRectUnion(gui_ios.dirtyRect, rect);
    [gui_ios.view_controller.view setNeedsDisplayInRect:gui_ios.dirtyRect];

}


/*
 * Cursor blink functions.
 *
 * This is a simple state machine:
 * BLINK_NONE	not blinking at all
 * BLINK_OFF	blinking, cursor is not shown
 * BLINK_ON blinking, cursor is shown
 */

    void
gui_mch_set_blinking(long wait, long on, long off)
{
//    printf("%s\n",__func__);
    gui_ios.blink_wait = wait;
    gui_ios.blink_on   = on;
    gui_ios.blink_off  = off;
}


/*
 * Start the cursor blinking.  If it was already blinking, this restarts the
 * waiting time and shows the cursor.
 */
    void
gui_mch_start_blink(void)
{
//    printf("%s\n",__func__);
    if (gui_ios.blink_timer != nil)
        [gui_ios.blink_timer invalidate];
    
    if (gui_ios.blink_wait && gui_ios.blink_on &&
        gui_ios.blink_off && gui.in_focus)
    {
        gui_ios.blink_timer = [NSTimer scheduledTimerWithTimeInterval: gui_ios.blink_wait / 1000.0
                                                               target: gui_ios.view_controller
                                                             selector: @selector(blinkCursorTimer:)
                                                             userInfo: nil
                                                              repeats: NO];
        gui_ios.blink_state = BLINK_ON;
        gui_update_cursor(TRUE, FALSE);
    }
}


/*
 * Stop the cursor blinking.  Show the cursor if it wasn't shown.
 */
    void
gui_mch_stop_blink(void)
{
//    printf("%s\n",__func__);  
    [gui_ios.blink_timer invalidate];
    
//    if (gui_ios.blink_state == BLINK_OFF)
//        gui_update_cursor(TRUE, FALSE);
    
    gui_ios.blink_state = BLINK_NONE;
    gui_ios.blink_timer = nil;
}


// -- Mouse -----------------------------------------------------------------


/*
 * Get current mouse coordinates in text window.
 */
    void
gui_mch_getmouse(int *x, int *y)
{
//    printf("%s\n",__func__);  
}


    void
gui_mch_setmouse(int x, int y)
{
//    printf("%s\n",__func__);  
}


    void
mch_set_mouse_shape(int shape)
{
//    printf("%s\n",__func__);  
}

     void
gui_mch_mousehide(int hide)
{
//    printf("%s\n",__func__);  
}


// -- Clip ----
//
    void
clip_mch_request_selection(VimClipboard *cbd)
{
//    printf("%s\n",__func__);  
}

    void
clip_mch_set_selection(VimClipboard *cbd)
{
//    printf("%s\n",__func__);  
}

   void
clip_mch_lose_selection(VimClipboard *cbd)
{
//    printf("%s\n",__func__);  
}

    int
clip_mch_own_selection(VimClipboard *cbd)
{
//    printf("%s\n",__func__);  
    return OK;
}


// -- Input Method ----------------------------------------------------------

#if defined(USE_IM_CONTROL)

    void
im_set_position(int row, int col)
{
//    printf("%s\n",__func__);  
}


    void
im_set_control(int enable)
{
//    printf("%s\n",__func__);  
}


    void
im_set_active(int active)
{
//    printf("%s\n",__func__);  
}


    int
im_get_status(void)
{
//    printf("%s\n",__func__);  
}

#endif // defined(USE_IM_CONTROL)





// -- Unsorted --------------------------------------------------------------



/*
 * Adjust gui.char_height (after 'linespace' was changed).
 */
    int
gui_mch_adjust_charheight(void)
{
//    printf("%s\n",__func__);  
    return OK;
}


    void
gui_mch_beep(void)
{
//    printf("%s\n",__func__);  
}



#ifdef FEAT_BROWSE
/*
 * Pop open a file browser and return the file selected, in allocated memory,
 * or NULL if Cancel is hit.
 *  saving  - TRUE if the file will be saved to, FALSE if it will be opened.
 *  title   - Title message for the file browser dialog.
 *  dflt    - Default name of file.
 *  ext     - Default extension to be added to files without extensions.
 *  initdir - directory in which to open the browser (NULL = current dir)
 *  filter  - Filter for matched files to choose from.
 *  Has a format like this:
 *  "C Files (*.c)\0*.c\0"
 *  "All Files\0*.*\0\0"
 *  If these two strings were concatenated, then a choice of two file
 *  filters will be selectable to the user.  Then only matching files will
 *  be shown in the browser.  If NULL, the default allows all files.
 *
 *  *NOTE* - the filter string must be terminated with TWO nulls.
 */
    char_u *
gui_mch_browse(
    int saving,
    char_u *title,
    char_u *dflt,
    char_u *ext,
    char_u *initdir,
    char_u *filter)
{
//    printf("%s\n",__func__);

    
    NSString *dir = [NSString stringWithFormat:@"%s", initdir];
    NSString *file = [NSString stringWithFormat:@"%s", dflt];
    NSString *path = [dir stringByAppendingString:file];

    NSLog(@"path: %@",path);
    NSURL *url = [NSURL fileURLWithPath:path];

    UIDocumentInteractionController *controller = [UIDocumentInteractionController interactionControllerWithURL:url];

    
    
    int height = gui_ios.view_controller.view.bounds.size.height;
   
   [controller presentOptionsMenuFromRect:CGRectMake(0,height-10,10,10) inView:gui_ios.view_controller.view animated: NO];

    return NULL;
}
#endif /* FEAT_BROWSE */



    int
gui_mch_dialog(
    int		type,
    char_u	*title,
    char_u	*message,
    char_u	*buttons,
    int		dfltbutton,
    char_u	*textfield,
    int         ex_cmd)     // UNUSED
{
//    printf("%s\n",__func__);
    return OK;
}


    void
gui_mch_flash(int msec)
{
//    printf("%s\n",__func__);  
    
}


guicolor_T
gui_mch_get_color(char_u *name)
{
    int i;
    int r, g, b;
    
    
    typedef struct GuiColourTable
    {
        char	    *name;
        guicolor_T     colour;
    } GuiColourTable;
    
    static GuiColourTable table[] =
    {
        {"Black",       RGB(0x00, 0x00, 0x00)},
        {"DarkGray",    RGB(0xA9, 0xA9, 0xA9)},
        {"DarkGrey",    RGB(0xA9, 0xA9, 0xA9)},
        {"Gray",        RGB(0xC0, 0xC0, 0xC0)},
        {"Grey",        RGB(0xC0, 0xC0, 0xC0)},
        {"LightGray",   RGB(0xD3, 0xD3, 0xD3)},
        {"LightGrey",   RGB(0xD3, 0xD3, 0xD3)},
        {"Gray10",      RGB(0x1A, 0x1A, 0x1A)},
        {"Grey10",      RGB(0x1A, 0x1A, 0x1A)},
        {"Gray20",      RGB(0x33, 0x33, 0x33)},
        {"Grey20",      RGB(0x33, 0x33, 0x33)},
        {"Gray30",      RGB(0x4D, 0x4D, 0x4D)},
        {"Grey30",      RGB(0x4D, 0x4D, 0x4D)},
        {"Gray40",      RGB(0x66, 0x66, 0x66)},
        {"Grey40",      RGB(0x66, 0x66, 0x66)},
        {"Gray50",      RGB(0x7F, 0x7F, 0x7F)},
        {"Grey50",      RGB(0x7F, 0x7F, 0x7F)},
        {"Gray60",      RGB(0x99, 0x99, 0x99)},
        {"Grey60",      RGB(0x99, 0x99, 0x99)},
        {"Gray70",      RGB(0xB3, 0xB3, 0xB3)},
        {"Grey70",      RGB(0xB3, 0xB3, 0xB3)},
        {"Gray80",      RGB(0xCC, 0xCC, 0xCC)},
        {"Grey80",      RGB(0xCC, 0xCC, 0xCC)},
        {"Gray90",      RGB(0xE5, 0xE5, 0xE5)},
        {"Grey90",      RGB(0xE5, 0xE5, 0xE5)},
        {"White",       RGB(0xFF, 0xFF, 0xFF)},
        {"DarkRed",     RGB(0x80, 0x00, 0x00)},
        {"Red",         RGB(0xFF, 0x00, 0x00)},
        {"LightRed",    RGB(0xFF, 0xA0, 0xA0)},
        {"DarkBlue",    RGB(0x00, 0x00, 0x80)},
        {"Blue",        RGB(0x00, 0x00, 0xFF)},
        {"LightBlue",   RGB(0xAD, 0xD8, 0xE6)},
        {"DarkGreen",   RGB(0x00, 0x80, 0x00)},
        {"Green",       RGB(0x00, 0xFF, 0x00)},
        {"LightGreen",  RGB(0x90, 0xEE, 0x90)},
        {"DarkCyan",    RGB(0x00, 0x80, 0x80)},
        {"Cyan",        RGB(0x00, 0xFF, 0xFF)},
        {"LightCyan",   RGB(0xE0, 0xFF, 0xFF)},
        {"DarkMagenta", RGB(0x80, 0x00, 0x80)},
        {"Magenta",	    RGB(0xFF, 0x00, 0xFF)},
        {"LightMagenta",RGB(0xFF, 0xA0, 0xFF)},
        {"Brown",       RGB(0x80, 0x40, 0x40)},
        {"Yellow",      RGB(0xFF, 0xFF, 0x00)},
        {"LightYellow", RGB(0xFF, 0xFF, 0xE0)},
        {"SeaGreen",    RGB(0x2E, 0x8B, 0x57)},
        {"Orange",      RGB(0xFF, 0xA5, 0x00)},
        {"Purple",      RGB(0xA0, 0x20, 0xF0)},
        {"SlateBlue",   RGB(0x6A, 0x5A, 0xCD)},
        {"Violet",      RGB(0xEE, 0x82, 0xEE)},
    };
    
    /* is name #rrggbb format? */
    if (name[0] == '#' && STRLEN(name) == 7)
    {
        r = hex_digit(name[1]) * 16 + hex_digit(name[2]);
        g = hex_digit(name[3]) * 16 + hex_digit(name[4]);
        b = hex_digit(name[5]) * 16 + hex_digit(name[6]);
        if (r < 0 || g < 0 || b < 0)
            return INVALCOLOR;
        return RGB(r, g, b);
    }
    
    for (i = 0; i < ARRAY_LENGTH(table); i++)
    {
        if (STRICMP(name, table[i].name) == 0)
            return table[i].colour;
    }
    
    /*
     * Last attempt. Look in the file "$VIMRUNTIME/rgb.txt".
     */
    {
#define LINE_LEN 100
        FILE	*fd;
        char	line[LINE_LEN];
        char_u	*fname;
        
        fname = expand_env_save((char_u *)"$VIMRUNTIME/rgb.txt");
        if (fname == NULL)
            return INVALCOLOR;
        
        fd = fopen((char *)fname, "rt");
        vim_free(fname);
        if (fd == NULL)
            return INVALCOLOR;
        
        while (!feof(fd))
        {
            int	    len;
            int	    pos;
            char    *color;
            
            fgets(line, LINE_LEN, fd);
            len = STRLEN(line);
            
            if (len <= 1 || line[len-1] != '\n')
                continue;
            
            line[len-1] = '\0';
            
            i = sscanf(line, "%d %d %d %n", &r, &g, &b, &pos);
            if (i != 3)
                continue;
            
            color = line + pos;
            
            if (STRICMP(color, name) == 0)
            {
                fclose(fd);
                return (guicolor_T)RGB(r, g, b);
            }
        }
        
        fclose(fd);
    }
    
    
    return INVALCOLOR;
}



/*
 * Return the RGB value of a pixel as long.
 */
    long_u
gui_mch_get_rgb(guicolor_T pixel)
{
//    printf("%s\n",__func__);  
    
    // This is only implemented so that vim can guess the correct value for
    // 'background' (which otherwise defaults to 'dark'); it is not used for
    // anything else (as far as I know).
    // The implementation is simple since colors are stored in an int as
    // "rrggbb".
    return pixel;
}


/*
 * Get the screen dimensions.
 * Understandably, Vim doesn't quite like it when the screen size changes
 * But on the iOS the screen is rotated quite often. So let's just pretend
 * that the screen is actually square, and large enough to contain the
 * actual screen in both portrait and landscape orientations.
 */
    void
gui_mch_get_screen_dimensions(int *screen_w, int *screen_h)
{
    CGSize appSize = [[UIScreen mainScreen] applicationFrame].size;
    int largest_dimension = MAX((int)appSize.width, (int)appSize.height);
    *screen_w = largest_dimension;
    *screen_h = largest_dimension;
}


/*
 * Return OK if the key with the termcap name "name" is supported.
 */
    int
gui_mch_haskey(char_u *name)
{
//    printf("%s\n",__func__);  
    return OK;
}


/*
 * Iconify the GUI window.
 */
    void
gui_mch_iconify(void)
{
//    printf("%s\n",__func__);  
    
}


#if defined(FEAT_EVAL) || defined(PROTO)
/*
 * Bring the Vim window to the foreground.
 */
    void
gui_mch_set_foreground(void)
{
//    printf("%s\n",__func__);  
}
#endif



    void
gui_mch_set_shellsize(
    int		width,
    int		height,
    int		min_width,
    int		min_height,
    int		base_width,
    int		base_height,
    int		direction)
{
//    printf("%s\n",__func__);
//    CGSize layerSize = CGLayerGetSize(gui_ios.layer);
//    gui_resize_shell(layerSize.width, layerSize.height);
}


/*
 * Set the position of the top left corner of the window to the given
 * coordinates.
 */
    void
gui_mch_set_winpos(int x, int y)
{
//    printf("%s\n",__func__);  
}


/*
 * Get the position of the top left corner of the window.
 */
    int
gui_mch_get_winpos(int *x, int *y)
{
//    printf("%s\n",__func__);  
    return OK;
}


    void
gui_mch_set_text_area_pos(int x, int y, int w, int h)
{
//    printf("%s\n",__func__);  
}



#ifdef FEAT_TITLE
/*
 * Set the window title and icon.
 * (The icon is not taken care of).
 */
    void
gui_mch_settitle(char_u *title, char_u *icon)
{
    int length = STRLEN(title);
    NSLog(@"%s\n",__func__);
    NSLog(@"Title %i", length);
}
#endif



    void
gui_mch_toggle_tearoffs(int enable)
{
//    printf("%s\n",__func__);  
}



    void
gui_mch_enter_fullscreen(int fuoptions_flags, guicolor_T bg)
{
//    printf("%s\n",__func__);  
}


    void
gui_mch_leave_fullscreen()
{
//    printf("%s\n",__func__);  
}


    void
gui_mch_fuopt_update()
{
//    printf("%s\n",__func__);  
}





#if defined(FEAT_SIGN_ICONS)
    void
gui_mch_drawsign(int row, int col, int typenr)
{
//    printf("%s\n",__func__);  
}

    void *
gui_mch_register_sign(char_u *signfile)
{
//    printf("%s\n",__func__);  
   return NULL;
}

    void
gui_mch_destroy_sign(void *sign)
{
//    printf("%s\n",__func__);  
}

#endif // FEAT_SIGN_ICONS



// -- Balloon Eval Support ---------------------------------------------------

#ifdef FEAT_BEVAL

    BalloonEval *
gui_mch_create_beval_area(target, mesg, mesgCB, clientData)
    void	*target;
    char_u	*mesg;
    void	(*mesgCB)__ARGS((BalloonEval *, int));
    void	*clientData;
{
//    printf("%s\n",__func__);  

    return NULL;
}

    void
gui_mch_enable_beval_area(beval)
    BalloonEval	*beval;
{
//    printf("%s\n",__func__);  
}

    void
gui_mch_disable_beval_area(beval)
    BalloonEval	*beval;
{
//    printf("%s\n",__func__);  
}

/*
 * Show a balloon with "mesg".
 */
    void
gui_mch_post_balloon(beval, mesg)
    BalloonEval	*beval;
    char_u	*mesg;
{
//    printf("%s\n",__func__);  
}

#endif // FEAT_BEVAL
