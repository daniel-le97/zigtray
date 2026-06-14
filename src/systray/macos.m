// macOS system tray implementation — adapted from fyne-io/systray.
// Compile with: -x objective-c -fobjc-arc
// Link with: -framework Cocoa

#import <Cocoa/Cocoa.h>
#include <stdbool.h>

// ── Callbacks implemented in Zig (via `export`) ────────────────────────
extern void systray_ready(void);
extern void systray_on_exit(void);
extern void systray_left_click(void);
extern void systray_right_click(void);
extern void systray_menu_item_selected(int menu_id);

// ── MenuItem helper class ──────────────────────────────────────────────

@interface MenuItem : NSObject
{
  @public
    NSNumber* menuId;
    NSNumber* parentMenuId;
    NSString* title;
    NSString* tooltip;
    short disabled;
    short checked;
}
-(id) initWithId: (int)theMenuId
withParentMenuId: (int)theParentMenuId
       withTitle: (const char*)theTitle
     withTooltip: (const char*)theTooltip
    withDisabled: (short)theDisabled
     withChecked: (short)theChecked;
@end

@implementation MenuItem
-(id) initWithId: (int)theMenuId
withParentMenuId: (int)theParentMenuId
       withTitle: (const char*)theTitle
     withTooltip: (const char*)theTooltip
    withDisabled: (short)theDisabled
     withChecked: (short)theChecked
{
  menuId = [NSNumber numberWithInt:theMenuId];
  parentMenuId = [NSNumber numberWithInt:theParentMenuId];
  title = [[NSString alloc] initWithCString:theTitle encoding:NSUTF8StringEncoding];
  tooltip = [[NSString alloc] initWithCString:theTooltip encoding:NSUTF8StringEncoding];
  disabled = theDisabled;
  checked = theChecked;
  return self;
}
@end

// ── Right-click detector view ──────────────────────────────────────────

@interface RightClickDetector : NSView
@property (copy) void (^onRightClicked)(NSEvent *);
@end

@implementation RightClickDetector
- (void)rightMouseUp:(NSEvent *)theEvent {
  if (!self.onRightClicked) return;
  self.onRightClicked(theEvent);
}
@end

// ── App delegate ───────────────────────────────────────────────────────

@interface SystrayAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
  - (void) add_or_update_menu_item:(MenuItem*) item;
  - (IBAction)menuHandler:(id)sender;
  - (void)menuWillOpen:(NSMenu*)menu;
  @property (assign) IBOutlet NSWindow *window;
@end

static NSMenuItem* find_menu_item(NSMenu *ourMenu, NSNumber *menuId);

@implementation SystrayAppDelegate
{
  NSStatusItem *statusItem;
  NSMenu *menu;
}

@synthesize window = _window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  self->statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
  self->menu = [[NSMenu alloc] init];
  self->menu.delegate = self;
  self->menu.autoenablesItems = FALSE;

  // Set the menu on the status item so the system shows it on click automatically.
  self->statusItem.menu = self->menu;
  self->statusItem.visible = TRUE;

  // Detect right clicks via a custom view overlay on the button.
  NSStatusBarButton *button = self->statusItem.button;
  NSSize size = [button frame].size;
  NSRect frame = CGRectMake(0, 0, size.width, size.height);
  RightClickDetector *rightClicker = [[RightClickDetector alloc] initWithFrame:frame];
  rightClicker.onRightClicked = ^(NSEvent *event) { [self rightMouseClicked]; };
  rightClicker.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  button.autoresizesSubviews = YES;
  [button addSubview:rightClicker];

  systray_ready();
}

- (void)rightMouseClicked { systray_right_click(); }

- (void)applicationWillTerminate:(NSNotification *)aNotification {
  systray_on_exit();
}

- (void)setIcon:(NSImage *)image {
  statusItem.button.image = image;
  [self updateTitleButtonStyle];
}

- (void)setTitle:(NSString *)title {
  statusItem.button.title = title;
  [self updateTitleButtonStyle];
}

- (void)updateTitleButtonStyle {
  if (statusItem.button.image != nil) {
    if ([statusItem.button.title length] == 0)
      statusItem.button.imagePosition = NSImageOnly;
    else
      statusItem.button.imagePosition = NSImageLeft;
  } else {
    statusItem.button.imagePosition = NSNoImage;
  }
}

- (void)setTooltip:(NSString *)tooltip {
  statusItem.button.toolTip = tooltip;
}

- (IBAction)menuHandler:(id)sender {
  NSNumber* menuId = [sender representedObject];
  systray_menu_item_selected(menuId.intValue);
}

- (void)menuWillOpen:(NSMenu *)menu { /* optional hook */ }

- (void)add_or_update_menu_item:(MenuItem *)item {
  NSMenu *theMenu = self->menu;
  if ([item->parentMenuId integerValue] > 0) {
    NSMenuItem *parentItem = find_menu_item(menu, item->parentMenuId);
    if (parentItem.hasSubmenu) {
      theMenu = parentItem.submenu;
    } else {
      theMenu = [[NSMenu alloc] init];
      [theMenu setAutoenablesItems:NO];
      [parentItem setSubmenu:theMenu];
    }
  }
  NSMenuItem *menuItem = find_menu_item(theMenu, item->menuId);
  if (menuItem == NULL) {
    menuItem = [theMenu addItemWithTitle:item->title
                                  action:@selector(menuHandler:)
                           keyEquivalent:@""];
    [menuItem setRepresentedObject:item->menuId];
  }
  [menuItem setTitle:item->title];
  [menuItem setTag:[item->menuId integerValue]];
  [menuItem setTarget:self];
  [menuItem setToolTip:item->tooltip];
  menuItem.enabled = (item->disabled == 1) ? FALSE : TRUE;
  menuItem.state = (item->checked == 1) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)add_separator:(NSNumber*)parentMenuId {
  if (parentMenuId.integerValue != 0) {
    NSMenuItem* menuItem = find_menu_item(menu, parentMenuId);
    if (menuItem != NULL) {
      [menuItem.submenu addItem:[NSMenuItem separatorItem]];
      return;
    }
  }
  [menu addItem:[NSMenuItem separatorItem]];
}

- (void)hide_menu_item:(NSNumber*)menuId {
  NSMenuItem* menuItem = find_menu_item(menu, menuId);
  if (menuItem != NULL) [menuItem setHidden:TRUE];
}

- (void)show_menu_item:(NSNumber*)menuId {
  NSMenuItem* menuItem = find_menu_item(menu, menuId);
  if (menuItem != NULL) [menuItem setHidden:FALSE];
}

- (void)remove_menu_item:(NSNumber*)menuId {
  NSMenuItem* menuItem = find_menu_item(menu, menuId);
  if (menuItem != NULL) [menuItem.menu removeItem:menuItem];
}

- (void)reset_menu { [self->menu removeAllItems]; }

- (void)show_menu {
  NSStatusBarButton *button = self->statusItem.button;
  [self->menu popUpMenuPositioningItem:nil
                            atLocation:NSMakePoint(0, button.frame.size.height + 5)
                                inView:button];
}

- (void)menuDidClose:(NSMenu *)menu {
  // No-op: menu is permanently attached to the status item.
}

- (void)quit {
  [NSApp stop:self];
  NSPoint eventLocation = NSMakePoint(0, 0);
  NSEvent *customEvent = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                            location:eventLocation
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:0
                                             context:nil
                                             subtype:0
                                               data1:0
                                               data2:0];
  [NSApp postEvent:customEvent atStart:NO];
}
@end

static NSMenuItem* find_menu_item(NSMenu *ourMenu, NSNumber *menuId) {
  NSMenuItem *foundItem = [ourMenu itemWithTag:[menuId integerValue]];
  if (foundItem != NULL) return foundItem;
  for (NSMenuItem *i_item in [ourMenu itemArray]) {
    if (i_item.hasSubmenu) {
      foundItem = find_menu_item(i_item.submenu, menuId);
      if (foundItem != NULL) return foundItem;
    }
  }
  return NULL;
}

// ── Global state ───────────────────────────────────────────────────────

static SystrayAppDelegate *owner = nil;

// ── C bridge functions (called from Zig) ───────────────────────────────

void registerSystray(void) {
  owner = [[SystrayAppDelegate alloc] init];
  [[NSApplication sharedApplication] setDelegate:owner];
  NSNotification *launched = [NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification
                                                          object:[NSApplication sharedApplication]];
  [owner applicationDidFinishLaunching:launched];
}

void nativeLoop(void) {
  [NSApp run];
}

void nativeEnd(void) {
  systray_on_exit();
}

void nativeStart(void) {
  owner = [[SystrayAppDelegate alloc] init];
  NSNotification *launched = [NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification
                                                          object:[NSApplication sharedApplication]];
  [owner applicationDidFinishLaunching:launched];
}

// ── Helpers ───────────────────────────────────────────────────────────

static void runInMainThread(SEL method, id object) {
  [owner performSelectorOnMainThread:method withObject:object waitUntilDone:YES];
}

// ── Public API (called from Zig) ───────────────────────────────────────

void setIcon(const char* iconBytes, int length, bool template) {
  NSData* buffer = [NSData dataWithBytes:iconBytes length:length];
  @autoreleasepool {
    NSImage *image = [[NSImage alloc] initWithData:buffer];
    [image setSize:NSMakeSize(16, 16)];
    image.template = template;
    runInMainThread(@selector(setIcon:), (id)image);
  }
}

void setTitle(char* ctitle) {
  NSString* title = [[NSString alloc] initWithCString:ctitle encoding:NSUTF8StringEncoding];
  free(ctitle);
  runInMainThread(@selector(setTitle:), (id)title);
}

void setTooltip(char* ctooltip) {
  NSString* tooltip = [[NSString alloc] initWithCString:ctooltip encoding:NSUTF8StringEncoding];
  free(ctooltip);
  runInMainThread(@selector(setTooltip:), (id)tooltip);
}

void add_or_update_menu_item(int menuId, int parentMenuId, char* title, char* tooltip, short disabled, short checked, short isCheckable) {
  MenuItem* item = [[MenuItem alloc] initWithId:menuId
                               withParentMenuId:parentMenuId
                                      withTitle:title
                                    withTooltip:tooltip
                                   withDisabled:disabled
                                    withChecked:checked];
  free(title);
  free(tooltip);
  runInMainThread(@selector(add_or_update_menu_item:), (id)item);
}

void add_separator(int menuId, int parentId) {
  NSNumber *pId = [NSNumber numberWithInt:parentId];
  runInMainThread(@selector(add_separator:), (id)pId);
}

void hide_menu_item(int menuId) {
  NSNumber *mId = [NSNumber numberWithInt:menuId];
  runInMainThread(@selector(hide_menu_item:), (id)mId);
}

void show_menu_item(int menuId) {
  NSNumber *mId = [NSNumber numberWithInt:menuId];
  runInMainThread(@selector(show_menu_item:), (id)mId);
}

void remove_menu_item(int menuId) {
  NSNumber *mId = [NSNumber numberWithInt:menuId];
  runInMainThread(@selector(remove_menu_item:), (id)mId);
}

void reset_menu(void) {
  runInMainThread(@selector(reset_menu), nil);
}

void show_menu(void) {
  runInMainThread(@selector(show_menu), nil);
}

void quit(void) {
  runInMainThread(@selector(quit), nil);
}
